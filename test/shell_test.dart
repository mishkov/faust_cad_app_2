import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('shell references faces and their shared edge geometry', () {
    final a = Vertex(Vector3.zero());
    final b = Vertex(Vector3(1, 0, 0));
    final shared = Edge(a, b, curve: const LinearCadCurve());
    Face triangle(Vertex third, Vector3 normal) => Face(
      surface: PlaneSurface(origin: a.vector, normal: normal),
      outerWire: Wire([
        shared,
        Edge(b, third, curve: const LinearCadCurve()),
        Edge(third, a, curve: const LinearCadCurve()),
      ]),
    );
    final first = triangle(Vertex(Vector3(0, 1, 0)), Vector3(0, 0, 1));
    final second = triangle(Vertex(Vector3(0, 0, 1)), Vector3(0, -1, 0));
    final shell = Shell(faces: [first, second]);

    expect(shell, isA<CadPrimitive>());
    expect(shell.faces[0], same(first));
    expect(shell.faces[1], same(second));
    expect(shell.faces[0].surface, same(first.surface));
    expect(shell.faces[0].outerWire, same(first.outerWire));
    expect(shell.faces[0].outerWire.edges.first, same(shared));
    expect(shell.faces[1].outerWire.edges.first, same(shared));
    expect(shell.faces[0].outerWire.edges.first.begin, same(a));
  });

  test('supports a closed cube, an open cube, and a single face', () {
    final faces = _cubeFaces();

    expect(Shell(faces: faces).faces, orderedEquals(faces));
    expect(Shell(faces: faces.take(5).toList()).faces, hasLength(5));
    expect(Shell(faces: [faces.first]).faces.single, same(faces.first));
    expect(Shell(faces: faces).isClosed, isTrue);
    expect(Shell(faces: faces.take(5).toList()).isClosed, isFalse);
    expect(Shell(faces: [faces.first]).isClosed, isFalse);
  });

  test('hole boundaries must also be paired to close a shell', () {
    final faces = _cubeFaces();
    final holeVertices = [
      Vertex(Vector3(0.2, 0.2, 1)),
      Vertex(Vector3(0.2, 0.8, 1)),
      Vertex(Vector3(0.8, 0.2, 1)),
    ];
    final top = faces[1];
    faces[1] = Face(
      surface: top.surface,
      outerWire: top.outerWire,
      innerWires: [_face(holeVertices).outerWire],
    );

    expect(Shell(faces: faces).isClosed, isFalse);
    faces.add(_face(holeVertices.reversed.toList()));
    expect(Shell(faces: faces).isClosed, isTrue);
  });

  test('connectivity is transitive and independent of face order', () {
    final a = Vertex(Vector3(0, 0, 0));
    final b = Vertex(Vector3(1, 0, 0));
    final c = Vertex(Vector3(2, 0, 0));
    final d = Vertex(Vector3(3, 0, 0));
    final first = _face([a, b, Vertex(Vector3(0, 1, 0))]);
    final middle = _face([b, c, Vertex(Vector3(1, 1, 0))]);
    final last = _face([c, d, Vertex(Vector3(2, 1, 0))]);
    final faces = [last, first, middle];

    expect(Shell(faces: faces).faces, orderedEquals(faces));
    expect(() => Shell(faces: [first, last]), throwsArgumentError);
  });

  test('inner boundaries can connect faces', () {
    final outer = _face([
      Vertex(Vector3(0, 0, 0)),
      Vertex(Vector3(4, 0, 0)),
      Vertex(Vector3(0, 4, 0)),
    ]);
    final hole = _face([
      Vertex(Vector3(1, 1, 0)),
      Vertex(Vector3(2, 1, 0)),
      Vertex(Vector3(1, 2, 0)),
    ]);
    final face = Face(
      surface: outer.surface,
      outerWire: outer.outerWire,
      innerWires: [hole.outerWire],
    );

    expect(Shell(faces: [face, hole]).faces, [face, hole]);
    expect(() => Shell(faces: [outer, hole]), throwsArgumentError);
  });

  test('rejects an empty shell and coincident but unshared topology', () {
    Face triangle() => _face([
      Vertex(Vector3.zero()),
      Vertex(Vector3(1, 0, 0)),
      Vertex(Vector3(0, 1, 0)),
    ]);

    expect(() => Shell(faces: []), throwsArgumentError);
    expect(() => Shell(faces: [triangle(), triangle()]), throwsArgumentError);
  });

  test('face collection cannot change after connectivity validation', () {
    final faces = _cubeFaces();
    final first = faces.first;
    final shell = Shell(faces: faces);
    faces.clear();

    expect(shell.faces, hasLength(6));
    expect(shell.faces.first, same(first));
    expect(() => shell.faces.clear(), throwsUnsupportedError);
    expect(() => shell.faces[0] = first, throwsUnsupportedError);
    expect(() => shell.faces.add(first), throwsUnsupportedError);
  });
}

Face _face(List<Vertex> vertices) => Face(
  surface: PlaneSurface(
    origin: vertices.first.vector,
    normal: (vertices[1].vector - vertices[0].vector).cross(
      vertices[2].vector - vertices[0].vector,
    ),
  ),
  outerWire: Wire([
    for (var i = 0; i < vertices.length; i++)
      Edge(
        vertices[i],
        vertices[(i + 1) % vertices.length],
        curve: const LinearCadCurve(),
      ),
  ]),
);

List<Face> _cubeFaces() {
  final vertices = [
    Vertex(Vector3(0, 0, 0)),
    Vertex(Vector3(1, 0, 0)),
    Vertex(Vector3(1, 1, 0)),
    Vertex(Vector3(0, 1, 0)),
    Vertex(Vector3(0, 0, 1)),
    Vertex(Vector3(1, 0, 1)),
    Vertex(Vector3(1, 1, 1)),
    Vertex(Vector3(0, 1, 1)),
  ];
  return [
    for (final indices in [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [1, 2, 6, 5],
      [2, 3, 7, 6],
      [3, 0, 4, 7],
    ])
      _face([for (final index in indices) vertices[index]]),
  ];
}
