import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/attachment_fixtures.dart';

void main() {
  test('hover lightens only visible material and outlines outer and hole boundaries', () async {
    final camera = CameraConfig(
      position: Vertex(Vector3(0, 0, 20)),
      yaw: 0,
      pitch: -math.pi / 2,
      focalLength: 200,
      focusDistance: 20,
    );
    final face = rectangle(
      PlanarFrame.xy(origin: Vector3(0, 0, 5)),
      hole: true,
    );
    final scene = SceneTessellator().buildGeometry([
      rectangle(PlanarFrame.xy()),
      face,
      rectangle(PlanarFrame.xy(origin: Vector3(4, 0, 8))),
    ], preserveSourceIdentity: true);
    Future<ByteData> render(bool hover) async {
      final recorder = ui.PictureRecorder();
      CadScenePainter(
        cameraConfig: camera,
        evaluatedScene: scene,
        renderMode: CadRenderMode.shaded,
        hoveredFace: hover ? face : null,
      ).paint(Canvas(recorder), const Size(400, 400));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 400);
      final data = (await image.toByteData())!;
      image.dispose();
      picture.dispose();
      return data;
    }

    final normal = await render(false), hover = await render(true);
    List<int> pixel(ByteData data, Vector3 world) {
      final projection = CameraProjection(camera);
      final p = projection.project(
        projection.toCameraSpace(world),
        screen: const Size(400, 400),
      );
      final i = (p.y.floor() * 400 + p.x.floor()) * 4;
      return [for (var c = 0; c < 3; c++) data.getUint8(i + c)];
    }

    final before = pixel(normal, Vector3(-2, 0, 5));
    final after = pixel(hover, Vector3(-2, 0, 5));
    expect(after[0], greaterThan(before[0]));
    expect(after[0], lessThan(before[0] + 40));
    expect(after[0], after[1]);
    for (final world in [Vector3(-4, 0, 5), Vector3(-1, 0, 5)]) {
      final edge = pixel(hover, world);
      expect(edge[1], greaterThan(edge[0] + 60));
      expect(edge[2], greaterThan(edge[0] + 60));
    }
    for (final world in [
      Vector3(-0.5, 0, 0),
      Vector3(2, 0, 8),
      Vector3(0, -2, 8),
    ]) {
      expect(pixel(hover, world), pixel(normal, world));
    }
    final mesh = MetalSceneMesh(scene);
    final lines = mesh.hoverLines(face);
    expect(lines.length ~/ 90, 8);
    expect([
      for (var i = 14; i < lines.length; i += 15) lines[i],
    ], everyElement(3));
    expect(mesh.hoverLines(null), isEmpty);
  });
}
