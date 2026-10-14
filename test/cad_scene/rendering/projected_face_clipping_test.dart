import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test(
    'nearer contour clipping retains holes and disconnected concave portions',
    () {
      final outer = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(0, 10),
      ];
      final hole = [
        const Offset(4, 4),
        const Offset(6, 4),
        const Offset(6, 6),
        const Offset(4, 6),
      ];
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon(outer, true)
        ..addPolygon(hole, true);
      final face = ProjectedFace(
        path,
        Vector3.zero(),
        Colors.white,
        contours: [outer, hole],
      );
      final nearer = face.closerRegion(Vector3(1, 0, -5));
      expect(nearer.contains(const Offset(7, 5)), true);
      expect(nearer.contains(const Offset(5.5, 5)), false);
      expect(nearer.contains(const Offset(2, 5)), false);
      final u = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(10, 10),
        const Offset(7, 10),
        const Offset(7, 3),
        const Offset(3, 3),
        const Offset(3, 10),
        const Offset(0, 10),
      ];
      final concave = ProjectedFace(
        Path()..addPolygon(u, true),
        Vector3.zero(),
        Colors.white,
        contours: [u],
      );
      final split = concave.closerRegion(Vector3(0, 1, -5));
      expect(split.contains(const Offset(1, 7)), true);
      expect(split.contains(const Offset(9, 7)), true);
      expect(split.contains(const Offset(5, 7)), false);
      expect(split.contains(const Offset(1, 2)), false);
    },
  );
}
