import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/cylindrical_assertions.dart';

void main() {
  test('default cylinder is one closed six-face analytic shell', () {
    final frame = PlanarFrame.xy();
    final object = Cylinder(frame: frame, radius: 3, height: 5);
    final solids = object.build();
    expect(solids, hasLength(1));
    expect(solids.single.shells, hasLength(1));
    expectCylindricalShell(
      solids.single.shells.single,
      frame: frame,
      radius: 3,
      height: 5,
      patchCount: 4,
    );
    // Builds are independent and do not share mutable topology.
    final other = object.build().single.shells.single;
    expect(other, isNot(same(solids.single.shells.single)));
    expect(
      other.faces.first.outerWire.edges.first.begin,
      isNot(
        same(
          solids.single.shells.single.faces.first.outerWire.edges.first.begin,
        ),
      ),
    );
  });

  test(
    'translated arbitrary axes and semicircle subdivisions remain exact',
    () {
      final frames = [
        PlanarFrame.xz(origin: Vector3(5, -8, 2)),
        PlanarFrame.yz(origin: Vector3(-3, 4, 9)),
        PlanarFrame.fromPlane(
          plane: PlaneSurface(
            origin: Vector3(7, -2, 4),
            normal: Vector3(-2, 3, -4),
          ),
          preferredDirection: Vector3(1, 1, 2),
        ),
      ];
      for (final frame in frames) {
        for (final count in [2, 3, 7]) {
          final solid = Cylinder(
            frame: frame,
            radius: 2.3,
            height: 4.7,
            patchCount: count,
          ).build().single;
          expect(solid.shells, hasLength(1));
          expectCylindricalShell(
            solid.shells.single,
            frame: frame,
            radius: 2.3,
            height: 4.7,
            patchCount: count,
          );
        }
      }
    },
  );

  test('invalid dimensions and unresolved placement are rejected', () {
    final frame = PlanarFrame.xy();
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => Cylinder(frame: frame, radius: value, height: 2),
        throwsArgumentError,
      );
      expect(
        () => Cylinder(frame: frame, radius: 2, height: value),
        throwsArgumentError,
      );
    }
    for (final count in [-1, 0, 1]) {
      expect(
        () => Cylinder(frame: frame, radius: 2, height: 3, patchCount: count),
        throwsArgumentError,
      );
    }
    expect(
      () => Cylinder(
        frame: PlanarFrame.xy(origin: Vector3(0, 0, 1e20)),
        radius: 2,
        height: 1,
      ).build(),
      throwsArgumentError,
    );
  });

  test('missing, duplicate, reversed, and mutated boundaries stay invalid', () {
    final shell = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 2,
      height: 3,
    ).build().single.shells.single;
    void reject(List<Face> faces) {
      final malformed = Shell(faces: faces);
      expect(malformed.isClosed, isFalse);
      expect(() => Solid(shells: [malformed]), throwsArgumentError);
    }

    reject(shell.faces.skip(1).toList());
    reject([...shell.faces, shell.faces.last]);
    reject([shell.faces.first.reversed(), ...shell.faces.skip(1)]);
    shell.faces.first.outerWire.edges.first.begin.vector.x += 0.1;
    expect(shell.isClosed, isFalse);
    expect(() => Solid(shells: [shell]), throwsArgumentError);
  });

  test('coincident vertices or independent circle geometry cannot pair', () {
    final shell = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 2,
      height: 3,
    ).build().single.shells.single;
    final cap = shell.faces.first;
    final original = cap.outerWire.edges;
    final circle = original.first.curve as CircularCadCurve;
    final independent = CircularCadCurve(
      frame: circle.frame,
      radius: circle.radius,
    );
    final vertices = [
      for (final edge in original) Vertex(edge.begin.vector.clone()),
    ];
    for (final copyVertices in [false, true]) {
      final capEdges = [
        for (var i = 0; i < original.length; i++)
          Edge(
            copyVertices ? vertices[i] : original[i].begin,
            copyVertices
                ? vertices[(i + 1) % original.length]
                : original[i].end,
            curve: copyVertices ? circle : independent,
            trim: original[i].trim,
          ),
      ];
      final replacement = Face(
        surface: cap.surface,
        outerWire: Wire(capEdges),
        orientation: cap.orientation,
      );
      final faces = [replacement, ...shell.faces.skip(1)];
      if (copyVertices) {
        expect(() => Shell(faces: faces), throwsArgumentError);
      } else {
        final malformed = Shell(faces: faces);
        expect(malformed.isClosed, isFalse);
        expect(() => Solid(shells: [malformed]), throwsArgumentError);
      }
    }
  });

  test('complementary arcs do not falsely close a cylindrical solid', () {
    final shell = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 2,
      height: 3,
    ).build().single.shells.single;
    final side = shell.faces[2];
    final first = side.outerWire.edges.first;
    final replacement = Edge(
      first.begin,
      first.end,
      curve: first.curve,
      trim: CircularTrim(
        startAngle: first.trim!.startAngle,
        sweepAngle: first.trim!.sweepAngle - 2 * math.pi,
      ),
    );
    final wrong = Face(
      surface: side.surface,
      outerWire: Wire([replacement, ...side.outerWire.edges.skip(1)]),
    );
    final malformed = Shell(
      faces: [shell.faces[0], shell.faces[1], wrong, ...shell.faces.skip(3)],
    );
    expect(malformed.isClosed, isFalse);
    expect(() => Solid(shells: [malformed]), throwsArgumentError);
  });
}
