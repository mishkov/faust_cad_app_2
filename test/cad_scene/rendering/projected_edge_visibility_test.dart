import 'package:faust_cad_app_2/cad_scene/rendering/projected_edge_visibility.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  final outer = [
    const Offset(20, 20),
    const Offset(80, 20),
    const Offset(80, 80),
    const Offset(20, 80),
  ];
  ProjectedFace face(List<List<Offset>> loops, [Vector3? depth]) =>
      ProjectedFace(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addPath(_path(loops), Offset.zero),
        depth ?? Vector3(0, 0, 0.2),
        Colors.grey,
        contours: loops,
      );
  EdgeCoverage classify(
    List<ProjectedFace> faces,
    Offset p,
    Offset q, {
    Vector3? depth,
    double bias = 1e-7,
  }) => ProjectedEdgeVisibility.classify(
    p,
    q,
    depth ?? Vector3(0, 0, 0.1),
    ProjectedFaceIndex(faces, const Size(100, 100)),
    bias: bias,
  );

  test('whole stroke inside a nearer face is hidden', () {
    expect(
      classify(
        [
          face([outer]),
        ],
        const Offset(30, 40),
        const Offset(70, 40),
      ),
      EdgeCoverage.hidden,
    );
  });
  test('clockwise contours have the same full-stroke visibility', () {
    expect(
      classify(
        [
          face([outer.reversed.toList()]),
        ],
        const Offset(30, 40),
        const Offset(70, 40),
      ),
      EdgeCoverage.hidden,
    );
  });
  test('self-crossing contours do not acquire convex half-planes', () {
    final star = [
      const Offset(50, 10),
      const Offset(73.5, 82.4),
      const Offset(12, 37.6),
      const Offset(88, 37.6),
      const Offset(26.5, 82.4),
    ];
    expect(face([star]).convexBoundary, isNull);
  });
  test('stroke outside the contour but inside its bounds is visible', () {
    final triangle = [
      const Offset(20, 20),
      const Offset(80, 20),
      const Offset(20, 80),
    ];
    expect(
      classify(
        [
          face([triangle]),
        ],
        const Offset(65, 70),
        const Offset(75, 70),
      ),
      EdgeCoverage.visible,
    );
  });
  test(
    'uncertain results retain only masks that can reach the full stroke',
    () {
      final irrelevant = face([
        [const Offset(20, 20), const Offset(80, 20), const Offset(20, 80)],
      ]);
      final crossing = face([
        [
          const Offset(68, 20),
          const Offset(80, 20),
          const Offset(80, 80),
          const Offset(68, 80),
        ],
      ]);
      final result = ProjectedEdgeVisibility.resolve(
        const Offset(65, 70),
        const Offset(75, 70),
        Vector3(0, 0, 0.1),
        ProjectedFaceIndex([irrelevant, crossing], const Size(100, 100)),
        bias: 1e-7,
      );
      expect(result.coverage, EdgeCoverage.uncertain);
      expect(result.occluders, [crossing]);
    },
  );
  test('crossing a contour retains isolated masking', () {
    expect(
      classify(
        [
          face([outer]),
        ],
        const Offset(10, 40),
        const Offset(90, 40),
      ),
      EdgeCoverage.uncertain,
    );
  });
  test('centre line inside does not prove full stroke coverage at a rim', () {
    expect(
      classify(
        [
          face([outer]),
        ],
        const Offset(30, 20.4),
        const Offset(70, 20.4),
      ),
      EdgeCoverage.uncertain,
    );
    expect(
      classify(
        [
          face([outer]),
        ],
        const Offset(30, 19.6),
        const Offset(70, 19.6),
      ),
      EdgeCoverage.uncertain,
    );
  });
  test('hole interior is visible and crossing a hole retains masking', () {
    final hole = [
      const Offset(35, 35),
      const Offset(65, 35),
      const Offset(65, 65),
      const Offset(35, 65),
    ];
    final occluder = face([outer, hole]);
    expect(
      classify([occluder], const Offset(40, 50), const Offset(60, 50)),
      EdgeCoverage.visible,
    );
    expect(
      classify([occluder], const Offset(30, 50), const Offset(70, 50)),
      EdgeCoverage.uncertain,
    );
  });
  test('concave notch is visible and crossing it retains masking', () {
    final loop = [
      const Offset(20, 20),
      const Offset(80, 20),
      const Offset(80, 80),
      const Offset(60, 80),
      const Offset(60, 40),
      const Offset(40, 40),
      const Offset(40, 80),
      const Offset(20, 80),
    ];
    expect(
      classify(
        [
          face([loop]),
        ],
        const Offset(45, 60),
        const Offset(55, 60),
      ),
      EdgeCoverage.visible,
    );
    expect(
      classify(
        [
          face([loop]),
        ],
        const Offset(30, 60),
        const Offset(70, 60),
      ),
      EdgeCoverage.uncertain,
    );
  });
  test('a stroke beside a hole rim retains full-coverage masking', () {
    final occluder = face([
      outer,
      [
        const Offset(35, 35),
        const Offset(65, 35),
        const Offset(65, 65),
        const Offset(35, 65),
      ],
    ]);
    for (final x in [34.6, 35.4]) {
      expect(
        classify([occluder], Offset(x, 45), Offset(x, 55)),
        EdgeCoverage.uncertain,
      );
    }
    expect(
      classify([occluder], const Offset(25, 45), const Offset(25, 55)),
      EdgeCoverage.hidden,
    );
  });
  test('local reciprocal-depth crossings retain masking', () {
    expect(
      classify(
        [
          face([outer], Vector3(0.002, 0, 0)),
        ],
        const Offset(30, 50),
        const Offset(70, 50),
      ),
      EdgeCoverage.uncertain,
    );
  });
  test('depth comparison includes the perpendicular stroke footprint', () {
    expect(
      classify(
        [
          face([outer], Vector3(0, 0.01, -0.399)),
        ],
        const Offset(30, 50),
        const Offset(70, 50),
      ),
      EdgeCoverage.uncertain,
    );
  });
  test('outline bias retains coplanar boundaries', () {
    expect(
      classify(
        [
          face([outer], Vector3(0, 0, 0.1)),
        ],
        const Offset(20, 20),
        const Offset(80, 20),
      ),
      EdgeCoverage.visible,
    );
  });
  test('wholly rearward surfaces do not mask an edge', () {
    expect(
      classify(
        [
          face([outer], Vector3(0, 0, 0.05)),
        ],
        const Offset(10, 50),
        const Offset(90, 50),
      ),
      EdgeCoverage.visible,
    );
  });
  test(
    'one complete occluder hides a stroke regardless of candidate order',
    () {
      final full = face([outer]);
      final crossing = face([
        [
          const Offset(45, 20),
          const Offset(55, 20),
          const Offset(55, 80),
          const Offset(45, 80),
        ],
      ]);
      for (final faces in [
        [full, crossing],
        [crossing, full],
      ]) {
        expect(
          classify(faces, const Offset(30, 50), const Offset(70, 50)),
          EdgeCoverage.hidden,
        );
      }
    },
  );
}

Path _path(List<List<Offset>> loops) {
  final result = Path()..fillType = PathFillType.evenOdd;
  for (final loop in loops) {
    result.addPolygon(loop, true);
  }
  return result;
}
