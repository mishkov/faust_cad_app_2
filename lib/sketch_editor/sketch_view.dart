import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

// Orthographic local-plane view. Pixel tolerances never enter the sketch model.
final class SketchView {
  const SketchView({
    this.scale = 5,
    this.center = Offset.zero,
    this.rotation = 0,
  });
  final double scale;
  final Offset center;

  final double rotation;

  Offset project(Vector2 point, Size size) {
    final x = point.x - center.dx, y = point.y - center.dy;
    return Offset(
      size.width / 2 +
          (x * math.cos(rotation) - y * math.sin(rotation)) * scale,
      size.height / 2 -
          (x * math.sin(rotation) + y * math.cos(rotation)) * scale,
    );
  }

  Vector2 unproject(Offset point, Size size) {
    final x = (point.dx - size.width / 2) / scale;
    final y = (size.height / 2 - point.dy) / scale;
    return Vector2(
      x * math.cos(rotation) + y * math.sin(rotation) + center.dx,
      -x * math.sin(rotation) + y * math.cos(rotation) + center.dy,
    );
  }

  SketchView pan(Offset pixels) {
    final shifted = unproject(-pixels, Size.zero);
    return SketchView(
      scale: scale,
      rotation: rotation,
      center: Offset(shifted.x, shifted.y),
    );
  }

  SketchView zoom(Offset cursor, Size size, double factor) {
    final anchor = unproject(cursor, size);
    final nextScale = (scale * factor).clamp(0.1, 500.0);
    final atNewScale = SketchView(
      scale: nextScale,
      rotation: rotation,
    ).unproject(cursor, size);
    return SketchView(
      scale: nextScale,
      rotation: rotation,
      center: Offset(anchor.x - atNewScale.x, anchor.y - atNewScale.y),
    );
  }
}
