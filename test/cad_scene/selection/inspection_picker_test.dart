import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/selection/selection_measurement.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_hit.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_picker.dart';
import 'package:faust_cad_app_2/document/evaluated_geometry.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/attachment_fixtures.dart';
import '../../support/extrusion_fixtures.dart';

import 'package:faust_cad_app_2/cad_scene/geometry/analytic_continuity.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';

const size = Size(400, 400);
final camera = CameraConfig(
  position: Vertex(Vector3(0, 0, 20)),
  yaw: 0,
  pitch: -math.pi / 2,
  focalLength: 200,
  focusDistance: 20,
);
ViewportPicker picker(List<CadPrimitive> geometry) => ViewportPicker(
  evaluated: EvaluatedGeometry(geometry: geometry, bodies: {}, faces: {}),
);
Offset project(Vector3 point, CameraConfig view) {
  final projection = CameraProjection(view);
  final p = projection.project(projection.toCameraSpace(point), screen: size);
  return Offset(p.x, p.y);
}

ViewportHit? pick(ViewportPicker scene, Vector3 point, {CameraConfig? view}) =>
    scene.pick(
      camera: view ?? camera,
      viewport: size,
      position: project(point, view ?? camera),
      mode: ViewportSelectionMode.inspect,
    );
Map<String, double> values(ViewportHit hit) => {
  for (final item in SelectionMeasurement.fromHit(hit).values)
    item.label: item.value,
};

void main() {
  for (final orthographic in [false, true]) {
    test(
      'visible edge wins within seven pixels, orthographic=$orthographic',
      () {
        final view = camera.copyWith(isOrthographic: orthographic);
        final face = rectangle(tiltedFrame(0.4));
        final scene = picker([face]);
        final edge = face.outerWire.edges.first;
        final p = project(edge.evaluate(0.5), view);
        final hit = scene.pick(
          camera: view,
          viewport: size,
          position: p + const Offset(0, 5),
          mode: ViewportSelectionMode.inspect,
        )!;
        expect(hit.edge, same(edge));
        expect(values(hit)['Length'], closeTo(8, 1e-10));
        expect(
          scene
              .pick(
                camera: view,
                viewport: size,
                position: p + const Offset(0, 8),
                mode: ViewportSelectionMode.inspect,
              )
              ?.edge,
          isNull,
        );
        expect(
          scene
              .pick(
                camera: view,
                viewport: size,
                position: p,
                mode: ViewportSelectionMode.planarFace,
              )!
              .edge,
          isNull,
        );
      },
    );
  }

  test(
    'occluded boundaries and standalone grid strokes cannot steal selection',
    () {
      final back = rectangle(PlanarFrame.xy());
      final front = rectangle(PlanarFrame.xy(origin: Vector3(0, 0, 5)));
      final grid = Edge(
        Vertex(Vector3(-2, 0, 6)),
        Vertex(Vector3(2, 0, 6)),
        curve: const LinearCadCurve(),
      );
      for (final geometry in [
        [back, front, grid],
        [grid, front, back],
      ]) {
        final scene = picker(geometry);
        final hidden = pick(scene, Vector3(0, -4, 0))!;
        expect(hidden.face, same(front));
        expect(hidden.edge, isNull);
        expect(pick(scene, Vector3.zero())!.edge, isNull);
        expect(pick(scene, Vector3(20, 20, 0)), isNull);
      }
    },
  );

  test(
    'cylinder walls are inspectable, artificial patch seams are not edges',
    () {
      final solid = Cylinder(
        frame: PlanarFrame.xy(),
        radius: 3,
        height: 6,
      ).build().single;
      final scene = picker([solid]);
      final view = CameraConfig(
        position: Vertex(Vector3(0, -20, 3)),
        yaw: 0,
        pitch: 0,
        focalLength: 200,
        focusDistance: 20,
      );
      final hit = pick(scene, Vector3(0, -3, 3), view: view)!;
      expect(hit.face.surface, isA<CylinderSurface>());
      expect(hit.edge, isNull);
      expect(SelectionMeasurement.fromHit(hit).kind, 'Cylinder');
      expect(values(hit), {'Radius': 3, 'Height': 6});
      final mesh = MetalSceneMesh(scene.scene);
      final walls = solid.shells.single.faces
          .where((f) => f.surface is CylinderSurface)
          .toSet();
      expect(mesh.selection(walls), hasLength(4));
    },
  );

  test('circular cap and rim use analytic radius and arc length', () {
    final solid = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 3,
      height: 6,
    ).build().single;
    final scene = picker([solid]);
    final cap = pick(scene, Vector3(0, 0, 6))!;
    expect(SelectionMeasurement.fromHit(cap).kind, 'Circle');
    expect(values(cap), {'Radius': 3});
    final rim = pick(scene, Vector3(3 / math.sqrt(2), 3 / math.sqrt(2), 6))!;
    expect(rim.edge, isNotNull);
    expect(values(rim)['Length'], closeTo(3 * math.pi / 2, 1e-9));
    expect(values(rim)['Radius'], 3);
    final mesh = MetalSceneMesh(scene.scene);
    expect(mesh.hoverLines(null, selectedEdge: rim.edge), isNotEmpty);
    expect(mesh.hoverLines(null), isEmpty);
  });

  test('inner cylindrical walls report hole dimensions', () {
    final solid = Tube(
      frame: PlanarFrame.xy(),
      outerRadius: 4,
      innerRadius: 2,
      height: 7,
    ).build().single;
    final face = solid.shells.single.faces.firstWhere(
      (face) =>
          face.surface is CylinderSurface &&
          face.orientation == FaceOrientation.reversed,
    );
    final hit = ViewportHit(
      face: face,
      owner: solid,
      point: Vector3.zero(),
      depth: 1,
    );
    expect(SelectionMeasurement.fromHit(hit).kind, 'Hole');
    expect(values(hit), {'Radius': 2, 'Height': 7});
  });

  test(
    'fresh geometry snapshots keep edge identity aligned with cached samples',
    () {
      final cache = SceneTessellator();
      ViewportPicker fresh() => ViewportPicker(
        evaluated: EvaluatedGeometry(
          geometry: Cube(
            centerPosition: Vertex(Vector3.zero()),
            size: 6,
          ).build(),
          bodies: {},
          faces: {},
        ),
        tessellator: cache,
      );
      final first = fresh();
      final oldHit = pick(first, Vector3(0, -3, 3))!;
      final scene = fresh();
      final hit = pick(scene, Vector3(0, -3, 3))!;
      expect(hit.edge, isNot(same(oldHit.edge)));
      expect(hit.edge, isNotNull);
      expect(scene.scene.edgeSamples.keys, contains(same(hit.edge)));
    },
  );
  test('extruded circles expose dimensions and continuous walls without seam targets', () {
    final regions = profileArrangement([profileCircle('circle', 0, 0, 3)]);
    final extrusion = const AnalyticExtrusionService().extrude(
      regions: regions,
      regionIds: regions.regions.map((r) => r.id),
      frame: PlanarFrame.xy(),
      distance: 6,
    );
    expect(extrusion.isValid, isTrue);
    final solid = extrusion.solids.single;
    final scene = picker([solid]);
    final cap = pick(scene, Vector3(0, 0, 6))!;
    expect(SelectionMeasurement.fromHit(cap).kind, 'Circle');
    expect(values(cap), {'Radius': 3});
    final view = CameraConfig(
      position: Vertex(Vector3(20, 0, 3)),
      yaw: math.pi / 2,
      pitch: 0,
      focalLength: 200,
      focusDistance: 20,
    );
    final wall = pick(scene, Vector3(3, 0, 3), view: view)!;
    expect(wall.edge, isNull);
    expect(values(wall), {'Radius': 3, 'Height': 6});
    final faces = solid.shells.single.faces;
    expect(
      AnalyticContinuity.connectedCylinderFaces(wall.face, faces),
      unorderedEquals(faces.where((f) => f.surface is CylinderSurface)),
    );
    final separated = Cylinder(
      frame: PlanarFrame.xy(origin: Vector3(0, 0, 10)),
      radius: 3,
      height: 6,
    ).build().single;
    expect(
      AnalyticContinuity.connectedCylinderFaces(wall.face, [
        ...faces,
        ...separated.shells.single.faces,
      ]),
      unorderedEquals(faces.where((f) => f.surface is CylinderSurface)),
    );
  });
}
