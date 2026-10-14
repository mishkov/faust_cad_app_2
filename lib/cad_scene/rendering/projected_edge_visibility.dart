import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'projected_face_index.dart';
import 'projected_face.dart';

enum EdgeCoverage { visible, hidden, uncertain }

/// Conservative visibility of a projected stroke, including its AA fringe.
///
/// A contour or depth boundary touching the swept stroke needs the renderer's
/// isolated mask. Testing only centre-line intervals loses partially covered
/// pixels at silhouettes, holes and intersections.
abstract final class ProjectedEdgeVisibility {
  static EdgeCoverage classify(
    Offset p,
    Offset q,
    Vector3 inverseDepth,
    ProjectedFaceIndex index, {
    required double bias,
    double coverageRadius = 1.5,
  }) => resolve(
    p,
    q,
    inverseDepth,
    index,
    bias: bias,
    coverageRadius: coverageRadius,
  ).coverage;

  /// Resolves full-stroke coverage and the faces that still require masking.
  ///
  /// Reuses one spatial query, discarding faces proven disjoint from the
  /// stroke's antialiasing support before constructing any depth masks.
  static ({EdgeCoverage coverage, List<ProjectedFace> occluders}) resolve(
    Offset p,
    Offset q,
    Vector3 inverseDepth,
    ProjectedFaceIndex index, {
    required double bias,
    double coverageRadius = 1.5,
  }) {
    final bounds = Rect.fromPoints(p, q).inflate(coverageRadius);
    List<ProjectedFace>? uncertain;
    for (final face in index.query(bounds)) {
      if (!bounds.overlaps(face.bounds)) continue;
      final a = face.inverseDepth.x - inverseDepth.x;
      final b = face.inverseDepth.y - inverseDepth.y;
      final c = face.inverseDepth.z - inverseDepth.z - bias;
      final atP = a * p.dx + b * p.dy + c;
      final atQ = a * q.dx + b * q.dy + c;
      // Use an enclosing square around the stroke, and include float path
      // rounding. This deliberately overestimates the actual butt-cap support.
      final fringe = coverageRadius * (a.abs() + b.abs());
      final tolerance =
          (a.abs() * bounds.right.abs() +
              a.abs() * bounds.left.abs() +
              b.abs() * bounds.top.abs() +
              b.abs() * bounds.bottom.abs() +
              c.abs()) *
          1e-6;
      if (math.max(atP, atQ) + fringe < -tolerance) continue;

      if (face.convexBoundary case final planes?) {
        var outside = false, inside = true;
        for (final plane in planes) {
          final pSide = plane.x * p.dx + plane.y * p.dy + plane.z;
          final qSide = plane.x * q.dx + plane.y * q.dy + plane.z;
          final rounding =
              (plane.x.abs() * (p.dx.abs() + q.dx.abs()) +
                  plane.y.abs() * (p.dy.abs() + q.dy.abs()) +
                  plane.z.abs()) *
              1e-6;
          if (math.max(pSide, qSide) + coverageRadius < -rounding) {
            outside = true;
            break;
          }
          if (math.min(pSide, qSide) - coverageRadius <= rounding) {
            inside = false;
          }
        }
        if (outside) continue;
        if (inside && math.min(atP, atQ) - fringe > tolerance) {
          return (coverage: EdgeCoverage.hidden, occluders: const []);
        }
        (uncertain ??= []).add(face);
        continue;
      }

      final inside = face.path.contains(p);
      var touchesBoundary = false;
      for (final contour in face.contours) {
        var previous = contour.last;
        for (final point in contour) {
          if (!touchesBoundary &&
              _near(p, q, previous, point, coverageRadius)) {
            touchesBoundary = true;
          }
          previous = point;
          if (touchesBoundary) break;
        }
        if (touchesBoundary) break;
      }
      if (touchesBoundary) {
        (uncertain ??= []).add(face);
      } else if (inside) {
        // With no contour crossing the whole swept stroke is in this face.
        // One wholly nearer face is sufficient, even if other faces cross it.
        if (math.min(atP, atQ) - fringe > tolerance) {
          return (coverage: EdgeCoverage.hidden, occluders: const []);
        }
        (uncertain ??= []).add(face);
      }
    }
    return (
      coverage: uncertain == null
          ? EdgeCoverage.visible
          : EdgeCoverage.uncertain,
      occluders: uncertain ?? const [],
    );
  }

  static bool _near(Offset p, Offset q, Offset a, Offset b, double radius) {
    final minX = math.min(a.dx, b.dx), maxX = math.max(a.dx, b.dx);
    final minY = math.min(a.dy, b.dy), maxY = math.max(a.dy, b.dy);
    if (maxX < math.min(p.dx, q.dx) - radius ||
        minX > math.max(p.dx, q.dx) + radius ||
        maxY < math.min(p.dy, q.dy) - radius ||
        minY > math.max(p.dy, q.dy) + radius) {
      return false;
    }
    double side(Offset u, Offset v, Offset w) =>
        (v.dx - u.dx) * (w.dy - u.dy) - (v.dy - u.dy) * (w.dx - u.dx);
    if (side(p, q, a) * side(p, q, b) <= 0 &&
        side(a, b, p) * side(a, b, q) <= 0) {
      return true;
    }
    final squared = radius * radius;
    return _distanceSquared(p, a, b) <= squared ||
        _distanceSquared(q, a, b) <= squared ||
        _distanceSquared(a, p, q) <= squared ||
        _distanceSquared(b, p, q) <= squared;
  }

  static double _distanceSquared(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final length = dx * dx + dy * dy;
    final t = length == 0
        ? 0.0
        : (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / length).clamp(0.0, 1.0);
    final x = p.dx - a.dx - t * dx, y = p.dy - a.dy - t * dy;
    return x * x + y * y;
  }
}
