import 'dart:ui' as ui;
import 'dart:io';

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/rendering.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/orbit_extrusion_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('partial circle extrusion paints throughout a bottom-view orbit', () {
    final sketch = orbitSketch();
    final scene = SceneTessellator().buildGeometry(orbitGeometry(sketch));
    for (final yaw in [-0.95, -1.2, -0.7, 0.0, 0.7]) {
      for (final pitch in [0.09, -0.4, -0.05, 0.0, 0.05, 0.3, 0.8, 1.2]) {
        final camera = CameraConfig(
          position: Vertex(
            Vector3(
              -89.31205501016781,
              -117.05489186439571,
              -47.35695643336397,
            ),
          ),
          yaw: yaw,
          pitch: pitch,
          focalLength: 500,
          focusDistance: 228.97747565806,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        ShadedSceneRenderer(camera).paint(canvas, const Size(743, 696), scene);
        expect(canvas.getSaveCount(), 1, reason: 'yaw $yaw pitch $pitch');
        recorder.endRecording().dispose();
      }
    }
  });

  testWidgets(
    'sketch overlay stays aligned after bottom-view rotation and viewport resize',
    (tester) async {
      final sketch = orbitSketch();
      final geometry = orbitGeometry(sketch);
      final scene = SceneTessellator().buildGeometry(geometry);
      final key = GlobalKey();
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(983, 696), const Size(880, 620)]) {
        await tester.binding.setSurfaceSize(size);
        for (final pitch in [0.09, 0.3, -0.05]) {
          final camera = CameraConfig(
            position: Vertex(
              Vector3(
                -89.31205501016781,
                -117.05489186439571,
                -47.35695643336397,
              ),
            ),
            yaw: -0.95,
            pitch: pitch,
            focalLength: 500,
            focusDistance: 228.97747565806,
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: Colors.white,
                  child: Row(
                    children: [
                      const SizedBox(width: 240),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CadScene(
                              cameraConfig: camera,
                              geometry: geometry,
                              renderMode: CadRenderMode.shaded,
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: SketchScenePainter(
                                  sketches: [sketch],
                                  camera: camera,
                                  occluders: scene,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final image = await tester.runAsync(
            () =>
                (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(),
          );
          final bytes = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final projection = CameraProjection(camera);
          final circle = sketch.solved.circles.values.single;
          final center = sketch.solved.points[circle.centerPointId]!.position;
          final position = projection.project(
            projection.toCameraSpace(
              Vector3(center.x - circle.radius, center.y, 0),
            ),
            screen: Size(size.width - 240, size.height),
          );
          final x = 240 + position.x.round(), y = position.y.round();
          var blue = false;
          for (var dx = -2; dx <= 2; dx++) {
            for (var dy = -2; dy <= 2; dy++) {
              final offset = ((y + dy) * size.width.toInt() + x + dx) * 4;
              if (bytes!.getUint8(offset + 2) > bytes.getUint8(offset) + 60) {
                blue = true;
              }
            }
          }
          expect(
            blue,
            true,
            reason: 'Sketch rim must be at its projected cap position after rotation/resize',
          );
          if (Platform.environment['ORBIT_RENDER_GALLERY'] != null &&
              pitch == 0.09 &&
              size.width == 983) {
            final png = await tester.runAsync(
              () => image!.toByteData(format: ui.ImageByteFormat.png),
            );
            await tester.runAsync(
              () =>
                  File(Platform.environment['ORBIT_RENDER_GALLERY']!)
                      .writeAsBytes(png!.buffer.asUint8List()),
            );
          }
          image!.dispose();
        }
      }
    },
  );
}
