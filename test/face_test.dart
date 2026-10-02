import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  late PlaneSurface surface;
  late Wire outer;
  late Wire hole;

  setUp(() {
    surface = PlaneSurface(origin: Vector3.zero(), normal: Vector3(0, 0, 1));
    outer = _rectangle(0, 4);
    hole = _rectangle(1, 2);
  });

  test('face references its surface and boundary topology', () {
    final face = Face(surface: surface, outerWire: outer, innerWires: [hole]);

    expect(face, isA<CadPrimitive>());
    expect(face.surface, same(surface));
    expect(face.outerWire, same(outer));
    expect(face.innerWires.single, same(hole));
    expect(face.outerWire.edges.first, same(outer.edges.first));
    expect(
      face.innerWires.single.edges.first.begin,
      same(hole.edges.first.begin),
    );
    expect(Face(surface: surface, outerWire: outer).innerWires, isEmpty);
  });

  test('faces can share a surface and wires without duplicating geometry', () {
    final first = Face(surface: surface, outerWire: outer);
    final second = Face(surface: surface, outerWire: outer, innerWires: [hole]);

    expect(first.surface, same(second.surface));
    expect(first.outerWire, same(second.outerWire));
  });

  test('face supports other mathematical surface implementations', () {
    const curvedSurface = _TestSurface();
    final face = Face(surface: curvedSurface, outerWire: outer);

    expect(face.surface, same(curvedSurface));
  });

  test('rejects an open outer boundary or any open hole', () {
    final open = Wire(outer.edges.take(3).toList());

    expect(() => Face(surface: surface, outerWire: open), throwsArgumentError);
    expect(
      () => Face(surface: surface, outerWire: outer, innerWires: [hole, open]),
      throwsArgumentError,
    );
  });

  test('matching endpoint coordinates cannot close a face boundary', () {
    final edges = outer.edges;
    final last = edges.last;
    final open = Wire([
      ...edges.take(3),
      Edge(last.begin, Vertex(last.end.vector.clone()), curve: last.curve),
    ]);

    expect(() => Face(surface: surface, outerWire: open), throwsArgumentError);
  });

  test('holes cannot be changed after boundary validation', () {
    final holes = [hole];
    final face = Face(surface: surface, outerWire: outer, innerWires: holes);
    holes.clear();

    expect(face.innerWires.single, same(hole));
    expect(() => face.innerWires.clear(), throwsUnsupportedError);
    expect(() => face.innerWires[0] = outer, throwsUnsupportedError);
    expect(() => face.innerWires.add(outer), throwsUnsupportedError);
  });
}

Wire _rectangle(double min, double max) {
  final vertices = [
    Vertex(Vector3(min, min, 0)),
    Vertex(Vector3(max, min, 0)),
    Vertex(Vector3(max, max, 0)),
    Vertex(Vector3(min, max, 0)),
  ];
  return Wire([
    for (var i = 0; i < vertices.length; i++)
      Edge(
        vertices[i],
        vertices[(i + 1) % vertices.length],
        curve: const LinearCadCurve(),
      ),
  ]);
}

class _TestSurface extends CadSurface {
  const _TestSurface();
}
