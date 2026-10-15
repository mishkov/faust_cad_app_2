import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../test/support/orbit_extrusion_fixture.dart';
import '../test/cad_scene/rendering/viewport_image_comparison_test.dart'
    show compareViewportImages, compareViewportSelectionImages;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native baseline images at nine camera angles and DPR 1/2', (
    tester,
  ) async {
    binding.reportData = {
      'image_comparisons': await tester.runAsync(compareViewportImages),
    };
  });
  testWidgets('native selection and object order after viewport resizing', (
    tester,
  ) async {
    await tester.runAsync(compareViewportSelectionImages);
  });
  testWidgets(
    'native GPU orbit preserves Material controls and visible solids',
    (tester) async {
      // Integration binding leaves the native keyboard connected. Register
      // the test channel explicitly so text entry also works in profile mode.
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final key = GlobalKey();
      final sketch = orbitSketch();
      final geometry = orbitGeometry(sketch);
      final occluders = SceneTessellator().buildGeometry(geometry);
      final orbit = ValueNotifier<int>(0);
      final enabled = ValueNotifier<bool>(false);
      addTearDown(orbit.dispose);
      addTearDown(enabled.dispose);
      final distance = TextEditingController(text: '10');
      addTearDown(distance.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 240,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sketches'),
                          DropdownButton<int>(
                            value: 0,
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('XY')),
                              DropdownMenuItem(value: 1, child: Text('YZ')),
                            ],
                            onChanged: (_) {},
                          ),
                          FilledButton(
                            key: const Key('gpu-material-button'),
                            onPressed: () {},
                            child: const Text('New sketch'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: distance,
                            decoration: const InputDecoration(
                              labelText: 'Distance',
                            ),
                          ),
                          const SwitchListTile(
                            value: true,
                            onChanged: null,
                            title: Text('Reverse'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: orbit,
                      builder: (context, step, _) {
                        final yaw = -0.9 + math.sin(step * 0.21) * 0.8,
                            pitch = -0.5 + math.sin(step * 0.15) * 0.65;
                        final forward = Vector3(
                          -math.sin(yaw) * math.cos(pitch),
                          math.cos(yaw) * math.cos(pitch),
                          math.sin(pitch),
                        );
                        final camera = CameraConfig(
                          position: Vertex(Vector3(35, 25, 5) - forward * 220),
                          yaw: yaw,
                          pitch: pitch,
                          focalLength: 500,
                          focusDistance: 220,
                        );
                        return ValueListenableBuilder<bool>(
                          valueListenable: enabled,
                          builder: (context, show, _) => Stack(
                            fit: StackFit.expand,
                            children: [
                              CadScene(
                                backend: CadRenderBackend.canvas,
                                cameraConfig: camera,
                                geometry: show ? geometry : const [],
                                renderMode: CadRenderMode.shaded,
                              ),
                              if (show)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: SketchScenePainter(
                                      sketches: [sketch],
                                      camera: camera,
                                      occluders: occluders,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.getRect(
        find.byKey(const Key('gpu-material-button')),
      );
      final sample = Offset(button.left + 12, button.center.dy);
      Future<(List<int>, int)> snapshot() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset =
            (sample.dy.round() * image.width + sample.dx.round()) * 4;
        final color = [for (var i = 0; i < 4; i++) bytes.getUint8(offset + i)];
        var gray = 0;
        for (var y = 20; y < image.height; y += 3) {
          for (var x = 250; x < image.width; x += 3) {
            final p = (y * image.width + x) * 4;
            final r = bytes.getUint8(p),
                g = bytes.getUint8(p + 1),
                b = bytes.getUint8(p + 2);
            if (r > 40 && r < 210 && (r - g).abs() < 4 && (g - b).abs() < 4) {
              gray++;
            }
          }
        }
        image.dispose();
        return (color, gray);
      }

      final baseline = (await snapshot()).$1;
      expect(baseline[2], greaterThan(baseline[1] + 10));
      enabled.value = true;
      for (var step = 0; step < 60; step++) {
        orbit.value = step;
        await tester.pump();
        expect(tester.takeException(), isNull);
        if (step % 3 == 0) {
          final actual = await snapshot();
          for (var i = 0; i < 4; i++) {
            expect(
              actual.$1[i],
              closeTo(baseline[i], 2),
              reason: 'Material button changed at orbit frame $step',
            );
          }
          expect(
            actual.$2,
            greaterThan(100),
            reason: 'Scene disappeared at orbit frame $step',
          );
        }
      }
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      expect(find.text('YZ'), findsOneWidget);
      await tester.tap(find.text('YZ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12');
      await tester.pumpAndSettle();
      expect(distance.text, '12');
      expect(tester.takeException(), isNull);
    },
  );
}
