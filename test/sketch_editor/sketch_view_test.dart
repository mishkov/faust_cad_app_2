import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'package:faust_cad_app_2/sketch_editor/sketch_view.dart';

void main() {
  test('a quarter-turn support maps local X up and local Y left', () {
    const view = SketchView(scale: 10, rotation: math.pi / 2);
    const size = Size(400, 300);
    expect(
      (view.project(Vector2(2, 0), size) - const Offset(200, 130)).distance,
      closeTo(0, 1e-10),
    );
    expect(
      (view.project(Vector2(0, 3), size) - const Offset(170, 150)).distance,
      closeTo(0, 1e-10),
    );
    expect(
      (view.unproject(const Offset(170, 130), size) - Vector2(2, 3)).length,
      closeTo(0, 1e-10),
    );
  });

  for (final rotation in [0.0, 0.7, -1.9, math.pi]) {
    test(
      'rotated support $rotation preserves drag and cursor zoom anchors',
      () {
        final view = SketchView(
          scale: 7,
          center: const Offset(13, -8),
          rotation: rotation,
        );
        const size = Size(700, 500);
        const drag = Offset(25, -40);
        final point = Vector2(21, -3);
        expect(
          (view.pan(drag).project(point, size) -
                  view.project(point, size) -
                  drag)
              .distance,
          closeTo(0, 1e-10),
        );
        const cursor = Offset(120, 340);
        final anchored = view.unproject(cursor, size);
        final zoomed = view.zoom(cursor, size, 1.8);
        expect(
          (zoomed.project(anchored, size) - cursor).distance,
          closeTo(0, 1e-10),
        );
        expect(zoomed.scale, closeTo(12.6, 1e-10));
        expect(zoomed.rotation, rotation);
      },
    );
  }
}
