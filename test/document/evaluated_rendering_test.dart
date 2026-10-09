import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  final camera = CameraConfig(
    position: Vertex(Vector3(0, -20, 10)),
    yaw: 0,
    pitch: -0.3,
    focalLength: 200,
    focusDistance: 20,
  );
  test('repeated paints never reconstruct legacy feature geometry', () {
    final object = _CountingCube();
    final painter = CadScenePainter(cameraConfig: camera, cadObjects: [object]);
    expect(object.builds, 1);
    _paintTwice(painter);
    expect(object.builds, 1);
    expect(painter.scene.faces, hasLength(6));
  });

  test('render input comes from valid evaluated bodies and cannot mutate document output', () {
    var evaluations = 0;
    FeatureDefinition cube(double size) => FeatureDefinition(
      id: FeatureId('a'),
      type: 'cube',
      parameters: {'x': 0, 'y': 0, 'z': 0, 'size': size},
    );
    final doc = CadDocument(
      evaluators: {
        'cube': (d, c) {
          evaluations++;
          return CubeFeature.evaluate(d, c);
        },
      },
      features: [cube(4)],
    );
    final before = doc.evaluation;
    final painter = CadScenePainter(
      cameraConfig: camera,
      geometry: before.geometry,
    );
    _paintTwice(painter);
    expect(evaluations, 1);
    expect(painter.scene.faces, hasLength(6));
    painter.scene.faces.first.source.outerWire.edges.first.begin.vector.x = 999;
    expect(
      (before.geometry.single as Solid)
          .shells
          .single
          .faces
          .first
          .outerWire
          .edges
          .first
          .begin
          .vector
          .x,
      -2,
    );
    doc.setFeature(cube(-1));
    final failed = CadScenePainter(
      cameraConfig: camera,
      geometry: doc.evaluation.geometry,
    );
    expect(failed.scene.faces, isEmpty);
    expect(failed.scene.edges, isEmpty);
    _paintTwice(failed);
    expect(evaluations, 2);
    expect(before.geometry, hasLength(1));
  });
}

void _paintTwice(CadScenePainter painter) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, const ui.Size(300, 300));
  painter.paint(canvas, const ui.Size(300, 300));
  recorder.endRecording().dispose();
}

class _CountingCube extends CadObject {
  int builds = 0;
  @override
  List<CadPrimitive> build() {
    builds++;
    return Cube(centerPosition: Vertex(Vector3.zero()), size: 4).build();
  }
}
