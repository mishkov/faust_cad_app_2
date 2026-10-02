import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// Vector rendering with per-region depth comparisons for planar CAD geometry.
///
/// Reciprocal depth is affine after perspective projection. Subtracting only
/// the closer part of each occluder handles intersecting faces and cyclic
/// overlaps that cannot be resolved by sorting whole faces or objects.
class ShadedSceneRenderer {
  ShadedSceneRenderer(CameraConfig camera)
    : _projection = CameraProjection(camera);

  final CameraProjection _projection;
  static final _light = Vector3(0.55, -0.65, 0.8).normalized();

  void paint(Canvas canvas, Size size, List<CadObject> objects) {
    final faces = <ProjectedFace>[];
    final edges = <({Edge edge, bool boundary})>[];

    void collect(CadPrimitive primitive, {bool boundary = false}) {
      switch (primitive) {
        case Solid(:final shells):
          for (final shell in shells) {
            collect(shell);
          }
        case Shell(:final faces):
          for (final face in faces) {
            collect(face);
          }
        case Face(:final outerWire, :final innerWires):
          final projected = _projectFace(primitive, size);
          if (projected != null) faces.add(projected);
          collect(outerWire, boundary: true);
          for (final wire in innerWires) {
            collect(wire, boundary: true);
          }
        case Wire(:final edges):
          for (final edge in edges) {
            collect(edge, boundary: boundary);
          }
        case Edge(curve: LinearCadCurve()):
          edges.add((edge: primitive, boundary: boundary));
      }
    }

    for (final object in objects) {
      for (final primitive in object.build()) {
        collect(primitive);
      }
    }

    for (final face in faces) {
      final visible = _visibleRegion(
        face.path,
        face.inverseDepth,
        faces,
        size,
        skip: face,
      );
      canvas.drawPath(visible, Paint()..color = face.color);
    }

    // Draw outlines and standalone geometry against the same face depths.
    // This also hides grid lines and cavity edges behind opaque material.
    // Boundary strokes finish last so antialiased hole rims stay black even
    // where a standalone line emerges from behind them.
    for (final (:edge, :boundary) in [
      ...edges.where((entry) => !entry.boundary),
      ...edges.where((entry) => entry.boundary),
    ]) {
      final clipped = _projection.clipLine(
        _projection.toCameraSpace(edge.begin.vector),
        _projection.toCameraSpace(edge.end.vector),
        screen: size,
      );
      if (clipped == null) continue;
      final begin = _projection.project(clipped.begin, screen: size);
      final end = _projection.project(clipped.end, screen: size);
      final p = Offset(begin.x, begin.y);
      final q = Offset(end.x, end.y);
      final delta = q - p;
      final lengthSquared = delta.distanceSquared;
      if (lengthSquared < 1e-12) continue;
      final gradient =
          (1 / clipped.end.y - 1 / clipped.begin.y) / lengthSquared;
      final inverseDepth = Vector3(
        delta.dx * gradient,
        delta.dy * gradient,
        1 / clipped.begin.y - gradient * (delta.dx * p.dx + delta.dy * p.dy),
      );
      final visible = _visibleRegion(
        Path()..addRect(Offset.zero & size),
        inverseDepth,
        faces,
        size,
        // A small relative bias retains boundaries on their own surfaces.
        bias: math.max(1 / clipped.begin.y, 1 / clipped.end.y) * 1e-6,
      );
      canvas.save();
      canvas.clipPath(visible);
      canvas.drawLine(
        p,
        q,
        Paint()
          ..color = boundary ? Colors.black : Colors.red
          ..strokeWidth = 1,
      );
      canvas.restore();
    }
  }

  ProjectedFace? _projectFace(Face face, Size size) {
    final surface = face.surface;
    if (surface is! PlaneSurface) return null;
    final origin = _projection.toCameraSpace(surface.origin);
    final normal = _projection.toCameraDirection(surface.normal);
    normal.normalize();
    final planeDistance = normal.dot(origin);
    // A plane through the eye projects to a line, not a fillable surface.
    if (planeDistance.abs() < 1e-10) return null;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final wire in [face.outerWire, ...face.innerWires]) {
      if (wire.edges.any((edge) => edge.curve is! LinearCadCurve)) return null;
      final loop = _projection.clipLoop([
        for (final edge in wire.edges)
          _projection.toCameraSpace(edge.begin.vector),
      ], screen: size);
      if (loop.length < 3) continue;
      final first = _projection.project(loop.first, screen: size);
      path.moveTo(first.x, first.y);
      for (final point in loop.skip(1)) {
        final projected = _projection.project(point, screen: size);
        path.lineTo(projected.x, projected.y);
      }
      path.close();
    }
    final focalLength = _projection.cameraConfig.focalLength;
    final a = normal.x / (focalLength * planeDistance);
    final b = -normal.z / (focalLength * planeDistance);
    final inverseDepth = Vector3(
      a,
      b,
      normal.y / planeDistance - a * size.width / 2 - b * size.height / 2,
    );
    // Faces are two-sided; choose the normal facing the camera. The light is
    // expressed in camera coordinates, so right/up stay brighter during orbit.
    if (planeDistance > 0) normal.negate();
    final brightness = 0.32 + 0.5 * math.max(0.0, normal.dot(_light));
    final gray = (255 * brightness).round();
    return ProjectedFace(
      path,
      inverseDepth,
      Color.fromARGB(255, gray, gray, gray),
    );
  }

  Path _visibleRegion(
    Path region,
    Vector3 inverseDepth,
    List<ProjectedFace> faces,
    Size size, {
    ProjectedFace? skip,
    double bias = 0,
  }) {
    for (final occluder in faces) {
      if (identical(occluder, skip) ||
          !region.getBounds().overlaps(occluder.path.getBounds())) {
        continue;
      }
      final difference = occluder.inverseDepth - inverseDepth;
      difference.z -= bias;
      final closerRegion = _positiveHalfPlane(difference, size);
      final hidden = Path.combine(
        PathOperation.intersect,
        occluder.path,
        closerRegion,
      );
      region = Path.combine(PathOperation.difference, region, hidden);
    }
    return region;
  }

  /// Clip the viewport to ax + by + c > 0 (the occluder is closer).
  Path _positiveHalfPlane(Vector3 coefficients, Size size) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    double distance(Offset p) =>
        coefficients.x * p.dx + coefficients.y * p.dy + coefficients.z;
    final points = <Offset>[];
    var previous = corners.last;
    var previousDistance = distance(previous);
    for (final point in corners) {
      final d = distance(point);
      if ((d > 0) != (previousDistance > 0)) {
        points.add(
          previous +
              (point - previous) * (previousDistance / (previousDistance - d)),
        );
      }
      if (d > 0) points.add(point);
      previous = point;
      previousDistance = d;
    }
    return Path()..addPolygon(points, true);
  }
}
