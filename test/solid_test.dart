import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'support/solid_fixtures.dart';

void main() {
  test('solid references its closed outer shell and original geometry', () {
    final shell = tetrahedronShell();
    final solid = Solid(shells: [shell]);

    expect(solid, isA<CadPrimitive>());
    expect(shell.isClosed, isTrue);
    expect(solid.shells.single, same(shell));
    expect(solid.shells.single.faces.first, same(shell.faces.first));
    expect(
      solid.shells.single.faces.first.outerWire.edges.first,
      same(shell.faces.first.outerWire.edges.first),
    );
  });

  test('preserves the outer shell and multiple cavity shells in order', () {
    final outer = tetrahedronShell(size: 10);
    final firstCavity = tetrahedronShell(origin: Vector3(1, 1, 1));
    final secondCavity = tetrahedronShell(origin: Vector3(3, 1, 1));
    final solid = Solid(shells: [outer, firstCavity, secondCavity]);

    expect(solid.shells[0], same(outer));
    expect(solid.shells[1], same(firstCavity));
    expect(solid.shells[2], same(secondCavity));
  });

  test('rejects empty, duplicate, and open shell boundaries', () {
    final closed = tetrahedronShell();
    final open = Shell(faces: closed.faces.take(3).toList());

    expect(open.isClosed, isFalse);
    expect(() => Solid(shells: []), throwsArgumentError);
    expect(() => Solid(shells: [closed, closed]), throwsArgumentError);
    expect(() => Solid(shells: [open]), throwsArgumentError);
    expect(() => Solid(shells: [closed, open]), throwsArgumentError);
  });

  test('shell collection cannot change after boundary validation', () {
    final shell = tetrahedronShell();
    final shells = [shell];
    final solid = Solid(shells: shells);
    shells.clear();

    expect(solid.shells.single, same(shell));
    expect(() => solid.shells.clear(), throwsUnsupportedError);
    expect(() => solid.shells.add(shell), throwsUnsupportedError);
    expect(() => solid.shells[0] = shell, throwsUnsupportedError);
  });

  test('rejects repeated faces and edges shared by more than two faces', () {
    final closed = tetrahedronShell();
    final face = closed.faces.first;
    final repeated = Shell(faces: [...closed.faces, face]);
    final extraFace = Face(surface: face.surface, outerWire: face.outerWire);
    final nonManifold = Shell(faces: [...closed.faces, extraFace]);

    expect(repeated.isClosed, isFalse);
    expect(nonManifold.isClosed, isFalse);
    expect(() => Solid(shells: [nonManifold]), throwsArgumentError);
  });

  test('rejects a closed skin with inconsistent boundary traversal', () {
    final faces = tetrahedronShell().faces.toList();
    final face = faces.first;
    faces[0] = triangle([
      for (final edge in face.outerWire.edges.reversed) edge.end,
    ]);
    final shell = Shell(faces: faces);

    expect(shell.isClosed, isFalse);
    expect(() => Solid(shells: [shell]), throwsArgumentError);
  });

  test('rejects closed skins touching at only a shared vertex', () {
    final corner = Vertex(Vector3.zero());
    final first = tetrahedronShell(corner: corner);
    final second = tetrahedronShell(corner: corner, size: -1);
    final pinched = Shell(faces: [...first.faces, ...second.faces]);

    expect(first.isClosed, isTrue);
    expect(second.isClosed, isTrue);
    expect(pinched.isClosed, isFalse);
    expect(() => Solid(shells: [pinched]), throwsArgumentError);
  });

  test('rejects coincident endpoints that are distinct vertex instances', () {
    final faces = tetrahedronShell().faces.toList();
    final face = faces.first;
    // Keep the face connected at one vertex, leaving its other vertices unshared.
    faces[0] = triangle([
      face.outerWire.edges.first.begin,
      for (final edge in face.outerWire.edges.skip(1))
        Vertex(edge.begin.vector.clone()),
    ]);

    expect(Shell(faces: faces).isClosed, isFalse);
  });

  test('matching endpoints do not merge distinct curved boundaries', () {
    final faces = tetrahedronShell().faces.toList();
    final face = faces.first;
    final original = face.outerWire.edges.first;
    faces[0] = Face(
      surface: face.surface,
      outerWire: Wire([
        Edge(original.begin, original.end, curve: const _TestCurve()),
        ...face.outerWire.edges.skip(1),
      ]),
    );

    expect(Shell(faces: faces).isClosed, isFalse);
  });

  test('independent linear curve instances still match shared endpoints', () {
    final faces = tetrahedronShell().faces.toList();
    final face = faces.first;
    faces[0] = Face(
      surface: face.surface,
      outerWire: Wire([
        for (final edge in face.outerWire.edges)
          Edge(edge.begin, edge.end, curve: LinearCadCurve()),
      ]),
    );

    expect(Shell(faces: faces).isClosed, isTrue);
  });

  test('rejects an edge paired within one face and a collapsed edge', () {
    final a = Vertex(Vector3.zero());
    final b = Vertex(Vector3(1, 0, 0));
    final surface = tetrahedronShell().faces.first.surface;
    for (final edges in [
      [
        Edge(a, b, curve: const LinearCadCurve()),
        Edge(b, a, curve: const LinearCadCurve()),
      ],
      [Edge(a, a, curve: const LinearCadCurve())],
    ]) {
      final shell = Shell(
        faces: [Face(surface: surface, outerWire: Wire(edges))],
      );

      expect(shell.isClosed, isFalse);
      expect(() => Solid(shells: [shell]), throwsArgumentError);
    }
  });

  test('rejects a face joining two boundary loops at a repeated vertex', () {
    final a = Vertex(Vector3.zero());
    final b = Vertex(Vector3(1, 0, 0));
    final c = Vertex(Vector3(0, 1, 0));
    final d = Vertex(Vector3(-1, 0, 0));
    final e = Vertex(Vector3(0, -1, 0));
    final shell = Shell(
      faces: [
        triangle([a, b, c, a, d, e]),
        triangle([a, c, b]),
        triangle([a, e, d]),
      ],
    );

    expect(shell.isClosed, isFalse);
    expect(() => Solid(shells: [shell]), throwsArgumentError);
  });
}

class _TestCurve extends CadCurve {
  const _TestCurve();
}
