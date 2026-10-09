import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_hit.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_picker.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/evaluated_geometry.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';

import '../../support/attachment_fixtures.dart';

const viewport = Size(400, 400);
final topCamera = CameraConfig(
  position: Vertex(Vector3(0, 0, 20)),
  yaw: 0,
  pitch: -math.pi / 2,
  focalLength: 200,
  focusDistance: 20,
);
Offset project(Vector3 point, CameraConfig camera) {
  final projection = CameraProjection(camera);
  final p = projection.project(
    projection.toCameraSpace(point),
    screen: viewport,
  );
  return Offset(p.x, p.y);
}

ViewportPicker picker(List<CadPrimitive> geometry) => ViewportPicker(
  evaluated: EvaluatedGeometry(geometry: geometry, bodies: {}, faces: {}),
);
ViewportHit? pick(
  ViewportPicker picker,
  Vector3 point, {
  CameraConfig? camera,
  ViewportSelectionMode mode = ViewportSelectionMode.planarFace,
}) => picker.pick(
  camera: camera ?? topCamera,
  viewport: viewport,
  position: project(point, camera ?? topCamera),
  mode: mode,
);
FeatureDefinition cube(double size, {double z = 0}) => FeatureDefinition(
  id: FeatureId('cube'),
  type: CubeFeature.type,
  parameters: {'x': 0, 'y': 0, 'z': z, 'size': size},
);

void main() {
  test('rotated planar face maps triangle to exact analytic object and world point', () {
    final frame = tiltedFrame(0.6, height: 3);
    final face = rectangle(frame);
    final p = frame.localToWorld(Vector2(2, 1));
    final hit = pick(picker([face]), p)!;
    expect(hit.face, same(face));
    expect(hit.owner, same(face));
    expect(hit.point.distanceTo(p), lessThan(1e-9));
    expect(frame.containsPoint(hit.point), isTrue);
    expect(hit.faceReference, isNull);
    hit.point.x = 999;
    expect(hit.point.x, isNot(999));
  });

  test('trimming holes expose background; frontmost surface wins independent of order', () {
    final front = rectangle(
      PlanarFrame.xy(origin: Vector3(0, 0, 5)),
      hole: true,
    );
    final back = rectangle(PlanarFrame.xy());
    for (final geometry in [
      [front, back],
      [back, front],
    ]) {
      final scene = picker(geometry);
      expect(pick(scene, Vector3.zero())!.face, same(back));
      expect(pick(scene, Vector3(2, 0, 5))!.face, same(front));
    }
    expect(pick(picker([front]), Vector3.zero()), isNull);
    expect(pick(picker([front]), Vector3(6, 0, 5)), isNull);
  });

  test(
    'analytic circular annulus bore stays open in rendered picking mesh',
    () {
      final tube = Tube(
        frame: PlanarFrame.xy(),
        outerRadius: 4,
        innerRadius: 1,
        height: 5,
      ).build().single;
      final scene = picker([tube]);
      expect(pick(scene, Vector3.zero()), isNull);
      final hit = pick(scene, Vector3(2, 0, 5))!;
      expect(hit.face.surface, isA<PlaneSurface>());
      expect(hit.point.z, closeTo(5, 1e-9));
      expect(hit.face.innerWires, hasLength(1));
    },
  );

  test('cylinder occludes planar back face and is rejected only after depth selection', () {
    final cylinder = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 3,
      height: 5,
    ).build().single;
    final back = rectangle(PlanarFrame.xz(origin: Vector3(0, 6, 2.5)));
    final sideCamera = CameraConfig(
      position: Vertex(Vector3(0, -20, 2.5)),
      yaw: 0,
      pitch: 0,
      focalLength: 200,
      focusDistance: 20,
    );
    for (final geometry in [
      [cylinder, back],
      [back, cylinder],
    ]) {
      final scene = picker(geometry);
      expect(pick(scene, Vector3(0, 0, 2.5), camera: sideCamera), isNull);
      final body = pick(
        scene,
        Vector3(0, 0, 2.5),
        camera: sideCamera,
        mode: ViewportSelectionMode.body,
      )!;
      expect(body.owner, same(cylinder));
      expect(body.face.surface, isNot(isA<PlaneSurface>()));
      expect(body.point.y, closeTo(-3, 0.02));
    }
  });

  test('evaluated body and named face references survive rebuild and fresh snapshots', () {
    final doc = CadDocument(
      evaluators: {CubeFeature.type: CubeFeature.evaluate},
      features: [cube(6)],
    );
    final first = doc.evaluation.materializeGeometry();
    final hit = pick(ViewportPicker(evaluated: first), Vector3.zero())!;
    expect(hit.faceReference!.key, 'top');
    expect(hit.bodyReference!.key, 'body');
    expect(first.faces[hit.face], hit.faceReference);
    expect(
      doc.evaluation.resolve(hit.faceReference!).status,
      ReferenceStatus.resolved,
    );
    final cache = SceneTessellator();
    final before = ViewportPicker(evaluated: first, tessellator: cache);
    final second = doc.evaluation.materializeGeometry();
    final after = ViewportPicker(evaluated: second, tessellator: cache);
    expect(
      pick(before, Vector3.zero())!.face,
      isNot(same(pick(after, Vector3.zero())!.face)),
    );
    expect(second.faces[pick(after, Vector3.zero())!.face], hit.faceReference);
    doc.setFeature(cube(10, z: 2));
    final updated = pick(
      ViewportPicker(evaluated: doc.evaluation.materializeGeometry()),
      Vector3.zero(),
    )!;
    expect(updated.faceReference, hit.faceReference);
    expect(updated.point.z, closeTo(7, 1e-9));
    expect(
      pick(ViewportPicker(evaluated: first), Vector3.zero())!.point.z,
      closeTo(3, 1e-9),
    );
    expect(
      pick(
        ViewportPicker(evaluated: first),
        Vector3.zero(),
        mode: ViewportSelectionMode.body,
      )!.bodyReference,
      hit.bodyReference,
    );
  });

  test('picked planar output attaches through evaluator and survives producer edits', () {
    final document = CadDocument(
      evaluators: {
        CubeFeature.type: CubeFeature.evaluate,
        'supported': (d, c) {
          final origin = c.support!.frame.origin;
          return CubeFeature.evaluate(
            FeatureDefinition(
              id: d.id,
              type: CubeFeature.type,
              parameters: {
                'x': origin.x,
                'y': origin.y,
                'z': origin.z,
                'size': 1,
              },
            ),
            c,
          );
        },
      },
      features: [cube(6)],
    );
    final picked = pick(
      ViewportPicker(evaluated: document.evaluation.materializeGeometry()),
      Vector3.zero(),
    )!;
    final attachedId = FeatureId('attached');
    document.setFeature(
      FeatureDefinition(
        id: attachedId,
        type: 'supported',
        support: PlanarSupport.face(
          reference: picked.faceReference!,
          preferredDirection: Vector3(1, 0, 0),
        ),
      ),
    );
    expect(
      document.evaluation.features[attachedId]!.support!.frame.origin.z,
      3,
    );
    expect(document.evaluation.geometry, hasLength(2));
    document.setFeature(cube(10));
    expect(
      document.evaluation.features[attachedId]!.support!.frame.origin.z,
      5,
    );
    document.removeFeature(FeatureId('cube'));
    expect(
      document.evaluation.features[attachedId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(
      document.evaluation.features[attachedId]!.diagnosticOutputs,
      isNotEmpty,
    );
    expect(document.evaluation.materializeGeometry().geometry, isEmpty);
  });

  test('semantic correspondence survives producer face-list reordering', () {
    final geometry = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 6,
    ).buildGeometry();
    final id = FeatureId('reordered');
    FeatureDefinition definition(bool reverse) => FeatureDefinition(
      id: id,
      type: 'reordered',
      parameters: {'reverse': reverse},
    );
    final document = CadDocument(
      evaluators: {
        'reordered': (d, c) {
          final faces = geometry.body.shells.single.faces;
          final body = Solid(
            shells: [
              Shell(
                faces: d.parameters['reverse'] == true
                    ? faces.reversed.toList()
                    : faces,
              ),
            ],
          );
          return [
            FeatureOutput(
              key: 'body',
              kind: OutputKind.body,
              geometry: body,
              faceKeys: geometry.planarFaces,
            ),
            for (final entry in geometry.planarFaces.entries)
              FeatureOutput(
                key: entry.key,
                kind: OutputKind.planarFace,
                geometry: entry.value,
              ),
          ];
        },
      },
      features: [definition(false)],
    );
    final before = pick(
      ViewportPicker(evaluated: document.evaluation.materializeGeometry()),
      Vector3.zero(),
    )!;
    document.setFeature(definition(true));
    final after = pick(
      ViewportPicker(evaluated: document.evaluation.materializeGeometry()),
      Vector3.zero(),
    )!;
    expect(before.faceReference!.key, 'top');
    expect(after.faceReference, before.faceReference);
    expect(after.point.distanceTo(before.point), lessThan(1e-9));
  });

  test('only explicitly named exact body faces are attachable; duplicates are not guessed', () {
    final geometry = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 6,
    ).buildGeometry();
    final top = geometry.planarFaces['top']!;
    expect(
      () => FeatureOutput(
        key: 'body',
        kind: OutputKind.body,
        geometry: geometry.body,
        faceKeys: {'wrong': rectangle(PlanarFrame.xy())},
      ),
      throwsArgumentError,
    );
    final id = FeatureId('producer');
    for (final ambiguous in [false, true]) {
      final doc = CadDocument(
        evaluators: {
          'fixture': (d, c) => [
            FeatureOutput(
              key: 'body',
              kind: OutputKind.body,
              geometry: geometry.body,
              faceKeys: {'cap': top},
            ),
            FeatureOutput(
              key: 'cap',
              kind: OutputKind.planarFace,
              geometry: top,
            ),
            if (ambiguous)
              FeatureOutput(
                key: 'cap',
                kind: OutputKind.planarFace,
                geometry: top,
              ),
          ],
        },
        features: [FeatureDefinition(id: id, type: 'fixture')],
      );
      final result = pick(
        ViewportPicker(evaluated: doc.evaluation.materializeGeometry()),
        Vector3.zero(),
      )!;
      if (ambiguous) {
        expect(result.faceReference, isNull);
      } else {
        expect(result.faceReference!.key, 'cap');
      }
    }
    final unnamed = CadDocument(
      evaluators: {
        'fixture': (d, c) => [
          FeatureOutput(
            key: 'body',
            kind: OutputKind.body,
            geometry: geometry.body,
          ),
          FeatureOutput(key: 'cap', kind: OutputKind.planarFace, geometry: top),
        ],
      },
      features: [FeatureDefinition(id: id, type: 'fixture')],
    );
    expect(
      pick(
        ViewportPicker(evaluated: unnamed.evaluation.materializeGeometry()),
        Vector3.zero(),
      )!.faceReference,
      isNull,
    );
  });

  test('viewport bounds, behind-eye geometry, and near-plane clipping match renderer', () {
    final front = rectangle(PlanarFrame.xz(origin: Vector3(0, 5, 0)));
    final behind = rectangle(PlanarFrame.xz(origin: Vector3(0, -2, 0)));
    final close = rectangle(PlanarFrame.xz(origin: Vector3(0, 5e-7, 0)));
    final camera = CameraConfig(
      position: Vertex(Vector3.zero()),
      yaw: 0,
      pitch: 0,
      focalLength: 200,
      focusDistance: 5,
    );
    final scene = picker([behind, close, front]);
    expect(
      scene
          .pick(
            camera: camera,
            viewport: viewport,
            position: const Offset(200, 200),
          )!
          .face,
      same(front),
    );
    expect(
      scene.pick(
        camera: camera,
        viewport: viewport,
        position: const Offset(-1, 200),
      ),
      isNull,
    );
    expect(
      scene.pick(camera: camera, viewport: Size.zero, position: Offset.zero),
      isNull,
    );
  });
}
