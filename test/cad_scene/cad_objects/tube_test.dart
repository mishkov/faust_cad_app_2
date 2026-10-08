import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/cylindrical_assertions.dart';

void main() {
  test('default tube has annular caps and inward walls in a single shell', () {
    final frame = PlanarFrame.xy();
    final object = Tube(
      frame: frame,
      outerRadius: 3,
      innerRadius: 1,
      height: 5,
    );
    final solids = object.build();
    expect(solids, hasLength(1));
    expect(solids.single.shells, hasLength(1));
    expectCylindricalShell(
      solids.single.shells.single,
      frame: frame,
      radius: 3,
      innerRadius: 1,
      height: 5,
      patchCount: 4,
    );
    final other = object.build().single.shells.single;
    expect(
      other.faces.first.innerWires.single.edges.first.begin,
      isNot(
        same(
          solids
              .single
              .shells
              .single
              .faces
              .first
              .innerWires
              .single
              .edges
              .first
              .begin,
        ),
      ),
    );
  });

  test(
    'arbitrary axes and multiple patch counts preserve the through-hole',
    () {
      final frames = [
        PlanarFrame.xz(origin: Vector3(-6, 8, 2)),
        PlanarFrame.yz(origin: Vector3(3, -4, 7)),
        PlanarFrame.fromPlane(
          plane: PlaneSurface(
            origin: Vector3(2, -5, 9),
            normal: Vector3(3, -2, -7),
          ),
          preferredDirection: Vector3(2, 1, 0),
        ),
      ];
      for (final frame in frames) {
        for (final count in [2, 3, 7]) {
          final solid = Tube(
            frame: frame,
            outerRadius: 2.8,
            innerRadius: 1.2,
            height: 4.3,
            patchCount: count,
          ).build().single;
          expect(solid.shells, hasLength(1));
          expectCylindricalShell(
            solid.shells.single,
            frame: frame,
            radius: 2.8,
            innerRadius: 1.2,
            height: 4.3,
            patchCount: count,
          );
        }
      }
    },
  );

  test('rejects invalid dimensions, bore sizes, and patch counts', () {
    final frame = PlanarFrame.xy();
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => Tube(frame: frame, outerRadius: value, innerRadius: 1, height: 3),
        throwsArgumentError,
      );
      expect(
        () => Tube(frame: frame, outerRadius: 2, innerRadius: value, height: 3),
        throwsArgumentError,
      );
      expect(
        () => Tube(frame: frame, outerRadius: 2, innerRadius: 1, height: value),
        throwsArgumentError,
      );
    }
    for (final inner in [2.0, 3.0]) {
      expect(
        () => Tube(frame: frame, outerRadius: 2, innerRadius: inner, height: 3),
        throwsArgumentError,
      );
    }
    for (final count in [-1, 0, 1]) {
      expect(
        () => Tube(
          frame: frame,
          outerRadius: 2,
          innerRadius: 1,
          height: 3,
          patchCount: count,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => Tube(
        frame: PlanarFrame.xy(origin: Vector3(0, 0, 1e20)),
        outerRadius: 2,
        innerRadius: 1,
        height: 1,
      ).build(),
      throwsArgumentError,
    );
  });

  test(
    'capping the bore, removing walls, or reversing inner normals fails',
    () {
      final shell = Tube(
        frame: PlanarFrame.xy(),
        outerRadius: 3,
        innerRadius: 1,
        height: 5,
      ).build().single.shells.single;
      final bottom = shell.faces.first;
      final plugged = Face(
        surface: bottom.surface,
        outerWire: bottom.outerWire,
        orientation: bottom.orientation,
      );
      final wrongHole = Face(
        surface: bottom.surface,
        outerWire: bottom.outerWire,
        innerWires: [bottom.innerWires.single.reversed()],
        orientation: bottom.orientation,
      );
      for (final faces in [
        [plugged, ...shell.faces.skip(1)],
        [wrongHole, ...shell.faces.skip(1)],
        shell.faces.take(6).toList(),
        [
          for (var i = 0; i < shell.faces.length; i++)
            i == 6 ? shell.faces[i].reversed() : shell.faces[i],
        ],
      ]) {
        final malformed = Shell(faces: faces);
        expect(malformed.isClosed, isFalse);
        expect(() => Solid(shells: [malformed]), throwsArgumentError);
      }
    },
  );
}
