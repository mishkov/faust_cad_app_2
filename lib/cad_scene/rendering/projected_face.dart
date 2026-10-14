import 'dart:ui' as ui;

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
  }) : contours = List.unmodifiable(
         contours.map((loop) => List<Offset>.unmodifiable(loop)),
       ),
       bounds = path.getBounds();

  final Path path;
  final Rect bounds;
  final List<List<Offset>> contours;

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

  /// At screen (x, y), reciprocal camera depth is ax + by + c.
  final Vector3 inverseDepth;
  final Color color;
}
