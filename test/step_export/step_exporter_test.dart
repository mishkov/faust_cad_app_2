import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/step_export/step_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

Solid cube({double size = 2, Vector3? center}) => Cube(
  centerPosition: Vertex(center ?? Vector3.zero()),
  size: size,
).build().single;

String export(List<Solid> solids) => const StepExporter().exportSolids(
  solids,
  timestamp: DateTime.utc(2026, 10, 15),
);

int entities(String data, String type) =>
    RegExp('^#[0-9]+=$type\\(', multiLine: true).allMatches(data).length;

void verifyReferences(String data) {
  final definitions = RegExp(
    r'^(#\d+)=',
    multiLine: true,
  ).allMatches(data).map((m) => m[1]!).toList();
  expect(definitions.toSet(), hasLength(definitions.length));
  for (final reference in RegExp(r'#\d+').allMatches(data)) {
    expect(definitions, contains(reference[0]));
  }
  final uses = <String, int>{};
  for (final edge in RegExp(
    r"ORIENTED_EDGE\('',\*,\*,(#\d+),",
  ).allMatches(data)) {
    uses.update(edge[1]!, (count) => count + 1, ifAbsent: () => 1);
  }
  expect(uses, hasLength(entities(data, 'EDGE_CURVE')));
  expect(uses.values, everyElement(2));
}

void main() {
  test('cube exports shared analytic topology, placement, and mm units', () {
    final data = export([cube(center: Vector3(4, 6, 8))]);
    expect(data, startsWith('ISO-10303-21;\nHEADER;'));
    expect(data, endsWith('ENDSEC;\nEND-ISO-10303-21;\n'));
    expect(data, contains("FILE_SCHEMA(('AUTOMOTIVE_DESIGN'))"));
    expect(data, contains('SI_UNIT(.MILLI.,.METRE.)'));
    expect(data, contains('2026-10-15T00:00:00.000Z'));
    expect(data, contains("CARTESIAN_POINT('',(3.0,5.0,7.0))"));
    expect(entities(data, 'MANIFOLD_SOLID_BREP'), 1);
    expect(entities(data, 'CLOSED_SHELL'), 1);
    expect(entities(data, 'ADVANCED_FACE'), 6);
    expect(entities(data, 'PLANE'), 6);
    expect(entities(data, 'VERTEX_POINT'), 8);
    expect(entities(data, 'EDGE_CURVE'), 12);
    expect(entities(data, 'LINE'), 12);
    verifyReferences(data);
  });

  test('complementary semicircles remain distinct on analytic cylinders', () {
    final data = export([
      Cylinder(
        frame: PlanarFrame.yz(origin: Vector3(3, 4, 5)),
        radius: 3,
        height: 8,
        patchCount: 2,
      ).build().single,
    ]);
    expect(entities(data, 'ADVANCED_FACE'), 4);
    expect(entities(data, 'CIRCLE'), 2);
    expect(entities(data, 'CYLINDRICAL_SURFACE'), 1);
    expect(entities(data, 'EDGE_CURVE'), 6);
    expect(entities(data, 'VERTEX_POINT'), 4);
    expect(data, isNot(contains('TRIANGULATED')));
    verifyReferences(data);
  });

  test('tube retains annular holes and reversed material faces', () {
    final data = export([
      Tube(
        frame: PlanarFrame.xy(),
        outerRadius: 3,
        innerRadius: 1,
        height: 8,
      ).build().single,
    ]);
    expect(entities(data, 'FACE_BOUND'), 2);
    expect(entities(data, 'CYLINDRICAL_SURFACE'), 2);
    expect(entities(data, 'CIRCLE'), 4);
    expect(
      RegExp(r"ADVANCED_FACE\([^\n]+,\.F\.\)").allMatches(data),
      hasLength(5),
    );
    verifyReferences(data);
  });

  test('cavity shells are voids rather than extra solid bodies', () {
    final inner = cube(size: 1).shells.single;
    final data = export([
      Solid(
        shells: [
          cube(size: 4).shells.single,
          Shell(faces: [for (final face in inner.faces) face.reversed()]),
        ],
      ),
    ]);
    expect(entities(data, 'BREP_WITH_VOIDS'), 1);
    expect(entities(data, 'MANIFOLD_SOLID_BREP'), 0);
    expect(entities(data, 'CLOSED_SHELL'), 2);
    expect(entities(data, 'ORIENTED_CLOSED_SHELL'), 1);
    verifyReferences(data);
  });

  test(
    'multiple coincident bodies retain independent topology and writer state',
    () {
      final body = cube();
      expect(export([body]), export([body]));
      final data = export([body, cube()]);
      expect(entities(data, 'MANIFOLD_SOLID_BREP'), 2);
      expect(entities(data, 'VERTEX_POINT'), 16);
      expect(entities(data, 'EDGE_CURVE'), 24);
      verifyReferences(data);
    },
  );

  test(
    'empty, collapsed, nonfinite, and unsupported input fail explicitly',
    () {
      expect(() => export([]), throwsStateError);
      for (final position in [Vector3.all(double.nan), Vector3.all(1)]) {
        final body = cube();
        for (final face in body.shells.single.faces) {
          for (final edge in face.outerWire.edges) {
            edge.begin.vector.setFrom(position);
          }
        }
        expect(() => export([body]), throwsA(isA<Error>()));
      }
      final shell = cube().shells.single;
      final unknownSurface = Solid(
        shells: [
          Shell(
            faces: [
              for (final face in shell.faces)
                Face(surface: _UnknownSurface(), outerWire: face.outerWire),
            ],
          ),
        ],
      );
      expect(() => export([unknownSurface]), throwsUnsupportedError);
      const curve = _UnknownCurve();
      final unknownCurve = Solid(
        shells: [
          Shell(
            faces: [
              for (final face in shell.faces)
                Face(
                  surface: face.surface,
                  outerWire: Wire([
                    for (final edge in face.outerWire.edges)
                      Edge(edge.begin, edge.end, curve: curve),
                  ]),
                ),
            ],
          ),
        ],
      );
      expect(() => export([unknownCurve]), throwsUnsupportedError);
    },
  );

  test('exponent coordinates use STEP real literal syntax', () {
    final data = export([cube(size: 1e-9, center: Vector3(0, 0, 1e-8))]);
    expect(data, contains('5.E-10'));
    expect(data, isNot(contains('5e-10')));
  });
}

class _UnknownSurface extends CadSurface {}

class _UnknownCurve extends CadCurve {
  const _UnknownCurve();
}
