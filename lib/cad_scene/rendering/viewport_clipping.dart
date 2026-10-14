import 'package:flutter/rendering.dart';

// Intersect the canvas with the viewport minus a bounded even-odd path. The
// viewport contour reverses material parity, including the occluder's holes,
// without asking the native path Boolean engine to combine near-shared edges.
void clipOutsidePath(
  Canvas canvas,
  Path path,
  Size size, {
  bool doAntiAlias = false,
}) {
  final complement = Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addPath(path, Offset.zero);
  canvas.clipPath(complement, doAntiAlias: doAntiAlias);
}
