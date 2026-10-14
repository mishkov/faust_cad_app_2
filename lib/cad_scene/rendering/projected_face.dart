import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A trimmed face and its affine reciprocal depth in viewport coordinates.
class ProjectedFace {
  ProjectedFace(
    this.path,
    this.inverseDepth,
    this.color, {
    required List<List<Offset>> contours,
    this.vertices,
    this.meshPoints,
    this.meshColors,
  }) : contours = List.unmodifiable(
         contours.map((loop) => List<Offset>.unmodifiable(loop)),
       ),
       bounds = path.getBounds();

  final Path path;
  final Rect bounds;
  final List<List<Offset>> contours;

  /// The inward unit half-planes of a convex contour, or `null` otherwise.
  ///
  /// Derived from this paint's projected contours; holes and concave shapes
  /// retain their original even-odd visibility checks.
  late final List<Vector3>? convexBoundary = _convexBoundary();

  List<Vector3>? _convexBoundary() {
    if (contours.length != 1) return null;
    final points = contours.single;
    var sign = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i],
          b = points[(i + 1) % points.length],
          c = points[(i + 2) % points.length];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross == 0) continue;
      if (sign != 0 && sign * cross < 0) return null;
      sign = cross.sign;
    }
    if (sign == 0) return null;
    final planes = <Vector3>[];
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      final x = (a.dy - b.dy) * sign, y = (b.dx - a.dx) * sign;
      final z = (a.dx * b.dy - b.dx * a.dy) * sign;
      // Check all vertices as well as local turns so self-crossing contours
      // cannot be mistaken for a convex polygon.
      for (var j = 0; j < points.length; j++) {
        if (j == i || j == (i + 1) % points.length) continue;
        final p = points[j];
        if (x * p.dx + y * p.dy + z < 0) return null;
      }
      final length = math.sqrt(x * x + y * y);
      if (length == 0) return null;
      planes.add(Vector3(x / length, y / length, z / length));
    }
    return planes;
  }

  // Clip the original bounded contours to the nearer-depth half-plane. Keeping
  // holes even-odd avoids native Boolean operations on repeatedly cut paths.
  Path closerRegion(Vector3 coefficients) {
    final path = Path()..fillType = PathFillType.evenOdd;
    double distance(Offset p) =>
        coefficients.x * p.dx + coefficients.y * p.dy + coefficients.z;
    for (final contour in contours) {
      final points = <Offset>[];
      var previous = contour.last;
      var previousDistance = distance(previous);
      for (final point in contour) {
        final d = distance(point);
        if ((d > 0) != (previousDistance > 0)) {
          points.add(
            previous +
                (point - previous) *
                    (previousDistance / (previousDistance - d)),
          );
        }
        if (d > 0) points.add(point);
        previous = point;
        previousDistance = d;
      }
      if (points.length >= 3) path.addPolygon(points, true);
    }
    return path;
  }

  final ui.Vertices? vertices;

  /// The original projected samples for deferred mesh submission.
  final List<Offset>? meshPoints;

  /// The interpolated colours at [meshPoints].
  final List<Color>? meshColors;

  /// Whether this face carries sampled mesh geometry.
  bool get isMesh => vertices != null || meshPoints != null;

  /// At screen (x, y), reciprocal camera depth is ax + by + c.
  final Vector3 inverseDepth;
  final Color color;
}
