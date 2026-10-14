import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

// Orthographic local-plane view. Pixel tolerances never enter the sketch model.
final class SketchView {
  const SketchView({this.scale = 5, this.center = Offset.zero});
  final double scale;
  final Offset center;

  Offset project(Vector2 point, Size size) => Offset(
    size.width / 2 + (point.x - center.dx) * scale,
    size.height / 2 - (point.y - center.dy) * scale,
  );

  Vector2 unproject(Offset point, Size size) => Vector2(
    (point.dx - size.width / 2) / scale + center.dx,
    (size.height / 2 - point.dy) / scale + center.dy,
  );

  SketchView pan(Offset pixels) => SketchView(
    scale: scale,
    center: center + Offset(-pixels.dx / scale, pixels.dy / scale),
  );

  SketchView zoom(Offset cursor, Size size, double factor) {
    final anchor = unproject(cursor, size);
    final nextScale = (scale * factor).clamp(0.1, 500.0);
    return SketchView(
      scale: nextScale,
      center: Offset(
        anchor.x - (cursor.dx - size.width / 2) / nextScale,
        anchor.y - (size.height / 2 - cursor.dy) / nextScale,
      ),
    );
  }
}
