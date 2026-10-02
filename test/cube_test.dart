import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('build returns one solid with a closed six-face shell', () {
    final solids = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 2,
    ).build();

    expect(solids, hasLength(1));
    expect(solids.single.shells, hasLength(1));
    final shell = solids.single.shells.single;
    expect(shell.isClosed, isTrue);
    expect(shell.faces, hasLength(6));
    for (final face in shell.faces) {
      expect(face.outerWire.isClosed, isTrue);
      expect(face.outerWire.edges, hasLength(4));
      expect(face.innerWires, isEmpty);
    }

    final edges = shell.faces.expand((face) => face.outerWire.edges).toList();
    expect(
      edges.map((edge) => edge.curve),
      everyElement(isA<LinearCadCurve>()),
    );
    final vertices = Set<Vertex>.identity()
      ..addAll(edges.expand((edge) => [edge.begin, edge.end]));
    expect(vertices, hasLength(8));
    for (final vertex in vertices) {
      final neighbors = Set<Vertex>.identity();
      for (final edge in edges) {
        if (identical(edge.begin, vertex)) neighbors.add(edge.end);
        if (identical(edge.end, vertex)) neighbors.add(edge.begin);
      }
      expect(neighbors, hasLength(3));
    }
  });

  test('faces follow the cube dimensions and point outward', () {
    final center = Vector3(5, -2, 7);
    const size = 3.5;
    final shell = Cube(
      centerPosition: Vertex(center),
      size: size,
    ).build().single.shells.single;

    final normals = <(double, double, double)>{};
    for (final face in shell.faces) {
      final plane = face.surface as PlaneSurface;
      final normal = plane.normal;
      normals.add((normal.x, normal.y, normal.z));
      final faceCenter = Vector3.zero();
      for (final edge in face.outerWire.edges) {
        final point = edge.begin.vector;
        faceCenter.add(point);
        final relative = point - center;
        expect(relative.x.abs(), size / 2);
        expect(relative.y.abs(), size / 2);
        expect(relative.z.abs(), size / 2);
        expect(normal.dot(point - plane.origin), closeTo(0, 1e-12));
        expect((edge.end.vector - point).length, closeTo(size, 1e-12));
      }
      faceCenter.scale(1 / 4);
      expect(normal.dot(faceCenter - center), closeTo(size / 2, 1e-12));
      final edges = face.outerWire.edges;
      final winding = (edges[0].end.vector - edges[0].begin.vector).cross(
        edges[1].end.vector - edges[1].begin.vector,
      );
      expect(winding.dot(normal), greaterThan(0));
    }
    expect(normals, {
      (-1.0, 0.0, 0.0),
      (1.0, 0.0, 0.0),
      (0.0, -1.0, 0.0),
      (0.0, 1.0, 0.0),
      (0.0, 0.0, -1.0),
      (0.0, 0.0, 1.0),
    });
    expect(center, Vector3(5, -2, 7));
  });
}
