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
import '../../support/extrusion_fixtures.dart';

import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';

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
  for (final mode in CadRenderMode.values) {
    test(
      'edge hover and selection use the same thicker stroke in $mode',
      () async {
        final camera = CameraConfig(
          position: Vertex(Vector3(0, 0, 20)),
          yaw: 0,
          pitch: -math.pi / 2,
          focalLength: 200,
          focusDistance: 20,
        );
        final face = rectangle(PlanarFrame.xy(origin: Vector3(0, 0, 5)));
        final scene = SceneTessellator().buildGeometry([
          face,
        ], preserveSourceIdentity: true);
        final edge = face.outerWire.edges.first;
        Future<ByteData> draw({
          bool selected = false,
          bool hovered = false,
        }) async {
          final recorder = ui.PictureRecorder();
          CadScenePainter(
            cameraConfig: camera,
            evaluatedScene: scene,
            renderMode: mode,
            selectedEdge: selected ? edge : null,
            hoveredEdge: hovered ? edge : null,
          ).paint(Canvas(recorder), const Size(400, 400));
          final picture = recorder.endRecording();
          final image = await picture.toImage(400, 400);
          final data = (await image.toByteData())!;
          image.dispose();
          picture.dispose();
          return data;
        }

        final selected = await draw(selected: true);
        final hovered = await draw(hovered: true);
        final both = await draw(selected: true, hovered: true);
        expect(
          hovered.buffer.asUint8List(),
          orderedEquals(selected.buffer.asUint8List()),
        );
        expect(
          both.buffer.asUint8List(),
          orderedEquals(selected.buffer.asUint8List()),
        );
        final projection = CameraProjection(camera);
        final center = projection.project(
          projection.toCameraSpace(Vector3(0, -4, 5)),
          screen: const Size(400, 400),
        );
        var cyanRows = 0;
        for (var y = center.y.floor() - 4; y <= center.y.ceil() + 4; y++) {
          final i = (y * 400 + center.x.round()) * 4;
          if (selected.getUint8(i + 1) > selected.getUint8(i) + 60 &&
              selected.getUint8(i + 2) > selected.getUint8(i) + 60) {
            cyanRows++;
          }
        }
        expect(cyanRows, greaterThanOrEqualTo(3));
        final mesh = MetalSceneMesh(scene);
        final selectedLines = mesh.hoverLines(null, selectedEdge: edge);
        expect(
          mesh.hoverLines(null, hoveredEdge: edge),
          orderedEquals(selectedLines),
        );
        expect(
          mesh.hoverLines(null, selectedEdge: edge, hoveredEdge: edge),
          orderedEquals(selectedLines),
        );
        expect([
          for (var i = 14; i < selectedLines.length; i += 15) selectedLines[i],
        ], everyElement(4));
      },
    );
  }

  for (final extruded in [false, true]) {
    test(
      'cylinder hover lights every patch and hides construction seams, extruded=$extruded',
      () async {
        final regions = profileArrangement([profileCircle('circle', 0, 0, 3)]);
        final solid = extruded
            ? const AnalyticExtrusionService()
                  .extrude(
                    regions: regions,
                    regionIds: regions.regions.map((r) => r.id),
                    frame: PlanarFrame.xy(),
                    distance: 6,
                  )
                  .solids
                  .single
            : Cylinder(
                frame: PlanarFrame.xy(),
                radius: 3,
                height: 6,
              ).build().single;
        final walls = solid.shells.single.faces
            .where((face) => face.surface is CylinderSurface)
            .toSet();
        final face = walls.last;
        final scene = SceneTessellator().buildGeometry([
          solid,
        ], preserveSourceIdentity: true);
        final camera = CameraConfig(
          position: Vertex(Vector3(0, -20, 3)),
          yaw: 0,
          pitch: 0,
          focalLength: 200,
          focusDistance: 20,
        );
        Future<ByteData> draw(bool hover) async {
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

        final before = await draw(false), after = await draw(true);
        final projection = CameraProjection(camera);
        for (final x in [-1.0, 1.0]) {
          final p = projection.project(
            projection.toCameraSpace(Vector3(x, -math.sqrt(8), 3)),
            screen: const Size(400, 400),
          );
          final i = (p.y.floor() * 400 + p.x.floor()) * 4;
          expect(after.getUint8(i), greaterThan(before.getUint8(i) + 5));
        }
        for (var y = 180; y <= 220; y++) {
          for (var x = 198; x <= 202; x++) {
            final i = (y * 400 + x) * 4;
            expect(after.getUint8(i + 1) - after.getUint8(i), lessThan(60));
          }
        }
        final mesh = MetalSceneMesh(scene);
        expect(mesh.hoverFaces(face), unorderedEquals(mesh.selection(walls)));
        final lines = mesh.hoverLines(face);
        expect(lines, isNotEmpty);
        for (var i = 0; i < lines.length; i += 90) {
          final az = lines[i + 2] + lines[i + 5];
          final bz = lines[i + 8] + lines[i + 11];
          expect(az, closeTo(bz, 1e-6));
          expect(az, anyOf(closeTo(0, 1e-6), closeTo(6, 1e-6)));
        }
      },
    );
  }
}
