import 'package:faust_cad_app_2/cad_scene/rendering/curved_triangle_visibility.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  final triangle = _face([
    const Offset(0, 0),
    const Offset(10, 0),
    const Offset(0, 10),
  ], mesh: true);
  ProjectedFaceIndex index(List<ProjectedFace> faces) =>
      ProjectedFaceIndex(faces, const Size(20, 20));
  final right = _face(_rectangle(5, -1, 11, 11), depth: Vector3(0, 0, 2));

  test('partial convex subtraction retains exact area and smooth RGBA', () {
    final resolver = CurvedTriangleVisibility()..beginFrame();
    expect(
      resolver.resolve(triangle, index([triangle, right]), bias: 0),
      TriangleCoverage.partial,
    );
    expect(_area(resolver), closeTo(37.5, 1e-10));
    for (var f = 0; f < resolver.fragmentCount; f++) {
      for (var v = 0; v < resolver.vertexCount(f); v++) {
        final x = resolver.component(f, v, 0), y = resolver.component(f, v, 1);
        expect(x, lessThanOrEqualTo(5));
        // The RGB field is the original projected fan's affine field.
        expect(
          resolver.component(f, v, 2),
          closeTo(255 * (1 - x / 10 - y / 10), 1e-10),
        );
        expect(resolver.component(f, v, 3), closeTo(255 * x / 10, 1e-10));
        expect(resolver.component(f, v, 4), closeTo(255 * y / 10, 1e-10));
        expect(resolver.component(f, v, 5), 255);
      }
    }
    expect(resolver.retainedFaceCount, 0);
  });
  test(
    'intersecting depth planes preserve local visibility in either order',
    () {
      final crossing = _face(
        _rectangle(-1, -1, 11, 11),
        depth: Vector3(0.1, 0, 0.5),
      );
      for (final faces in [
        [triangle, crossing],
        [crossing, triangle],
      ]) {
        final resolver = CurvedTriangleVisibility()..beginFrame();
        expect(
          resolver.resolve(triangle, index(faces), bias: 0),
          TriangleCoverage.partial,
        );
        expect(_area(resolver), closeTo(37.5, 1e-10));
        expect(_contains(resolver, const Offset(2, 2)), true);
        expect(_contains(resolver, const Offset(7, 1)), false);
      }
    },
  );
  test('overlapping masks subtract their union without double-erasing', () {
    final top = _face(_rectangle(-1, 5, 11, 11), depth: Vector3(0, 0, 2));
    for (final masks in [
      [right, top],
      [top, right],
    ]) {
      final resolver = CurvedTriangleVisibility()..beginFrame();
      expect(
        resolver.resolve(triangle, index([triangle, ...masks]), bias: 0),
        TriangleCoverage.partial,
      );
      expect(_area(resolver), closeTo(25, 1e-10));
      expect(_contains(resolver, const Offset(2, 2)), true);
      expect(_contains(resolver, const Offset(2, 7)), false);
    }
  });
  test('coplanar and farther faces keep the original triangle', () {
    final resolver = CurvedTriangleVisibility()..beginFrame();
    for (final depth in [1.0, 0.5]) {
      final cover = _face(
        _rectangle(-1, -1, 11, 11),
        depth: Vector3(0, 0, depth),
      );
      expect(
        resolver.resolve(triangle, index([triangle, cover]), bias: 0),
        TriangleCoverage.visible,
      );
      expect(_area(resolver), closeTo(50, 1e-10));
    }
  });
  test('fully hidden triangles need no fragments', () {
    final cover = _face(_rectangle(-1, -1, 11, 11), depth: Vector3(0, 0, 2));
    final resolver = CurvedTriangleVisibility()..beginFrame();
    expect(
      resolver.resolve(triangle, index([triangle, cover]), bias: 0),
      TriangleCoverage.hidden,
    );
    expect(resolver.fragmentCount, 0);
  });
  test('disjoint contours with overlapping bounds do not fragment', () {
    final cover = _face([
      const Offset(10, 2),
      const Offset(10, 10),
      const Offset(2, 10),
    ], depth: Vector3(0, 0, 2));
    final resolver = CurvedTriangleVisibility()..beginFrame();
    expect(
      resolver.resolve(triangle, index([triangle, cover]), bias: 0),
      TriangleCoverage.visible,
    );
    expect(resolver.fragmentCount, 1);
  });
  test('holes and concave occluders request the isolated mask fallback', () {
    final outer = _rectangle(-1, -1, 11, 11), hole = _rectangle(2, 2, 4, 4);
    final holed = ProjectedFace(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon(outer, true)
        ..addPolygon(hole, true),
      Vector3(0, 0, 2),
      Colors.white,
      contours: [outer, hole],
    );
    final concave = _face([
      const Offset(1, 1),
      const Offset(8, 1),
      const Offset(8, 8),
      const Offset(5, 3),
      const Offset(1, 8),
    ], depth: Vector3(0, 0, 2));
    for (final cover in [holed, concave]) {
      final resolver = CurvedTriangleVisibility()..beginFrame();
      expect(
        resolver.resolve(triangle, index([triangle, cover]), bias: 0),
        TriangleCoverage.fallback,
      );
      expect(resolver.fragmentCount, 0);
      expect(resolver.retainedFaceCount, 0);
    }
  });
  test(
    'fragment, vertex, candidate, face and frame budgets fail atomically',
    () {
      final middle = _face(_rectangle(2, -1, 4, 11), depth: Vector3(0, 0, 2));
      for (final resolver in [
        CurvedTriangleVisibility(maxFragments: 1),
        CurvedTriangleVisibility(maxPolygonVertices: 3),
        CurvedTriangleVisibility(maxCandidates: 1),
        CurvedTriangleVisibility(maxFaceWork: 1),
        CurvedTriangleVisibility(maxFrameWork: 1),
      ]) {
        resolver.beginFrame();
        expect(
          resolver.resolve(triangle, index([triangle, middle]), bias: 0),
          TriangleCoverage.fallback,
        );
        expect(resolver.fragmentCount, 0);
        expect(resolver.retainedFaceCount, 0);
        expect(resolver.frameWork, lessThanOrEqualTo(resolver.maxFrameWork));
      }
    },
  );
  test('frame budgets reset and never reuse previous geometry or index', () {
    final resolver = CurvedTriangleVisibility(maxFrameWork: 1)..beginFrame();
    expect(
      resolver.resolve(triangle, index([triangle, right]), bias: 0),
      TriangleCoverage.fallback,
    );
    resolver.beginFrame();
    expect(resolver.frameWork, 0);
    expect(
      resolver.resolve(triangle, index([triangle]), bias: 0),
      TriangleCoverage.visible,
    );
    expect(_area(resolver), 50);
    expect(resolver.retainedFaceCount, 0);
  });
  test('clipped fans preserve each original cell colour field', () {
    final points = _rectangle(0, 0, 10, 10);
    final fan = _face(points, mesh: true);
    final resolver = CurvedTriangleVisibility()..beginFrame();
    expect(
      resolver.resolve(fan, index([fan, right]), bias: 0),
      TriangleCoverage.partial,
    );
    expect(_area(resolver), closeTo(50, 1e-10));
    // Lower fan uses red/blue/white, upper uses red/green/blue.
    for (var f = 0; f < resolver.fragmentCount; f++) {
      for (var v = 0; v < resolver.vertexCount(f); v++) {
        final x = resolver.component(f, v, 0) / 10,
            y = resolver.component(f, v, 1) / 10;
        final expected = y <= x
            ? [255 * (1 - x), 255 * (x - y), 255 * y]
            : [255 * (1 - x), 255 * (y - x), 255 * y];
        for (var c = 0; c < 3; c++) {
          expect(resolver.component(f, v, c + 2), closeTo(expected[c], 1e-10));
        }
      }
    }
  });
  test(
    'pixel contacts keep isolated coverage while clear boundaries batch',
    () {
      final resolver = CurvedTriangleVisibility()..beginFrame();
      final faces = index([triangle, right]);
      expect(
        resolver.resolve(triangle, faces, bias: 0, pixelScaleX: 1),
        TriangleCoverage.fallback,
      );
      expect(resolver.fragmentCount, 0);
      expect(
        resolver.resolve(
          triangle,
          faces,
          bias: 0,
          pixelScaleX: 1,
          pixelTranslateX: 0.3,
        ),
        TriangleCoverage.partial,
      );
      expect(_area(resolver), closeTo(37.5, 1e-10));
    },
  );
  test('depth precision is not narrowed to float before clipping', () {
    const base = 100000000.0;
    final precise = _face(
      _rectangle(-1, -1, 11, 11),
      depth: Vector3(0, 0, base + 0.01),
    );
    final target = _face(
      triangle.meshPoints!,
      mesh: true,
      depth: Vector3(0, 0, base),
    );
    final resolver = CurvedTriangleVisibility()..beginFrame();
    expect(
      resolver.resolve(target, index([target, precise]), bias: 0),
      TriangleCoverage.hidden,
    );
  });
}

List<Offset> _rectangle(double l, double t, double r, double b) => [
  Offset(l, t),
  Offset(r, t),
  Offset(r, b),
  Offset(l, b),
];
ProjectedFace _face(List<Offset> points, {bool mesh = false, Vector3? depth}) =>
    ProjectedFace(
      Path()..addPolygon(points, true),
      depth ?? Vector3(0, 0, 1),
      Colors.white,
      contours: [points],
      meshPoints: mesh ? points : null,
      meshColors: mesh
          ? [
              const Color(0xffff0000),
              const Color(0xff00ff00),
              const Color(0xff0000ff),
              if (points.length == 4) Colors.white,
            ]
          : null,
    );
double _area(CurvedTriangleVisibility r) {
  var result = 0.0;
  for (var f = 0; f < r.fragmentCount; f++) {
    var cross = 0.0;
    for (var i = 0; i < r.vertexCount(f); i++) {
      final j = (i + 1) % r.vertexCount(f);
      cross +=
          r.component(f, i, 0) * r.component(f, j, 1) -
          r.component(f, j, 0) * r.component(f, i, 1);
    }
    result += cross.abs() / 2;
  }
  return result;
}

bool _contains(CurvedTriangleVisibility r, Offset p) {
  for (var f = 0; f < r.fragmentCount; f++) {
    final points = [
      for (var v = 0; v < r.vertexCount(f); v++)
        Offset(r.component(f, v, 0), r.component(f, v, 1)),
    ];
    if ((Path()..addPolygon(points, true)).contains(p)) return true;
  }
  return false;
}
