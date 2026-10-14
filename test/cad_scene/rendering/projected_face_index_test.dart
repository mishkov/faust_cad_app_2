import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  ProjectedFace face(Rect bounds) {
    final contour = [
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
    return ProjectedFace(
      Path()..addPolygon(contour, true),
      Vector3(0, 0, 1),
      Colors.white,
      contours: [contour],
    );
  }

  test('queries deduplicate faces across cells in stable input order', () {
    final faces = [
      face(const Rect.fromLTRB(40, 40, 90, 90)),
      face(const Rect.fromLTRB(0, 0, 100, 100)),
      face(const Rect.fromLTRB(0, 0, 15, 15)),
    ];
    final index = ProjectedFaceIndex(faces, const Size(100, 100));
    final first = index.query(const Rect.fromLTRB(0, 0, 100, 100));
    final second = index.query(const Rect.fromLTRB(70, 70, 80, 80));
    expect(second, orderedEquals(faces.take(2)));
    // Outstanding iterables and subsequent queries must keep their own results.
    expect(first, orderedEquals(faces));
    expect(
      index.query(const Rect.fromLTRB(0, 0, 10, 10)),
      orderedEquals(faces.skip(1)),
    );
    expect(
      index.query(const Rect.fromLTRB(0, 0, 100, 100)),
      orderedEquals(faces),
    );
  });
}
