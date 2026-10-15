import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../test/support/orbit_extrusion_fixture.dart';
import 'support/metal_image_validation.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final go = Completer<void>();
  developer.registerExtension('ext.cad.startBenchmark', (method, args) async {
    if (!go.isCompleted) go.complete();
    return developer.ServiceExtensionResponse.result('{}');
  });
  setUpAll(() async {
    if (const bool.fromEnvironment('VIEWPORT_WAIT_FOR_FOCUS')) {
      runApp(
        const MaterialApp(home: Scaffold(body: Text('Focus Metal validation'))),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      debugPrint('VIEWPORT_FOCUS_READY');
      await go.future.timeout(const Duration(minutes: 2));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  });
  testWidgets('Metal native capture, presentation, revisions and disposal', (
    tester,
  ) async {
    final controller = MetalViewportController();
    final sketch = orbitSketch(), geometry = orbitGeometry(orbitSketch());
    CameraConfig camera(double yaw, double pitch) {
      final forward = Vector3(
        -math.sin(yaw) * math.cos(pitch),
        math.cos(yaw) * math.cos(pitch),
        math.sin(pitch),
      );
      return CameraConfig(
        position: Vertex(Vector3(35, 25, 5) - forward * 220),
        yaw: yaw,
        pitch: pitch,
        focalLength: 500,
        focusDistance: 220,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  children: [
                    const Text('Metal validation'),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('New sketch'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CadScene(
                  backend: CadRenderBackend.metal,
                  metalController: controller,
                  cameraConfig: camera(-.95, -.5),
                  geometry: geometry,
                  sketches: [sketch],
                  renderMode: CadRenderMode.shaded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await controller.ready;
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    expect(controller.error.value, isNull);
    final report = <String, dynamic>{};
    await tester.runAsync(() async {
      final stats = await controller.stats();
      expect(stats['error'], isNull);
      final capture = await controller.capture();
      final pixels = capture['bgra'] as Uint8List;
      expect(pixels.where((v) => v < 220).length, greaterThan(1000));
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        capture['width'] as int,
        capture['height'] as int,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      final image = await completer.future;
      report['images'] = {
        'smoke': base64Encode(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        ),
      };
      image.dispose();
      report['stats'] = stats;
      if (const bool.fromEnvironment('METAL_CHECK_IMAGES')) {
        report.addAll(await validateMetalImages(controller));
      }
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final environment = await MetalViewportController.channel
          .invokeMapMethod<String, dynamic>('environment');
      expect(environment!['activeRenderers'], 0);
      report['environment'] = environment;
    });
    binding.reportData = report;
  });
  testWidgets(
    'Metal keeps input working through resize, hide and repeated disposal',
    (tester) async {
      tester.testTextInput.register();
      addTearDown(tester.testTextInput.unregister);
      final geometry = orbitGeometry(orbitSketch());
      for (var cycle = 0; cycle < 6; cycle++) {
        final controller = MetalViewportController();
        final size = ValueNotifier<Size>(const Size(320, 240));
        final camera = ValueNotifier<CameraConfig>(
          CameraConfig(
            position: Vertex(Vector3(0, -200, 100)),
            yaw: 0,
            pitch: -.4,
            focalLength: 500,
            focusDistance: 220,
          ),
        );
        final text = TextEditingController();
        var taps = 0, drags = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    onPressed: () => taps++,
                    child: const Text('Control'),
                  ),
                  TextField(controller: text),
                  Expanded(
                    child: Center(
                      child: ValueListenableBuilder<Size>(
                        valueListenable: size,
                        builder: (context, s, _) => SizedBox(
                          width: s.width,
                          height: s.height,
                          child: GestureDetector(
                            onPanUpdate: (e) {
                              drags++;
                              camera.value = camera.value.pan(e.delta);
                            },
                            child: ValueListenableBuilder<CameraConfig>(
                              valueListenable: camera,
                              builder: (context, c, _) => CadScene(
                                backend: CadRenderBackend.metal,
                                metalController: controller,
                                cameraConfig: c,
                                geometry: geometry,
                                renderMode: CadRenderMode.shaded,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Control'));
        expect(taps, 1);
        await tester.enterText(find.byType(TextField), '12.5');
        expect(text.text, '12.5');
        await tester.drag(find.byType(CadScene), const Offset(35, 10));
        await tester.pump();
        expect(drags, greaterThan(0));
        for (final s in const [Size(560, 400), Size(0, 0), Size(300, 200)]) {
          size.value = s;
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(controller.error.value, isNull);
          final stats = await controller.stats();
          expect(stats['error'], isNull);
          expect(stats['targetGeneration'], greaterThanOrEqualTo(2));
          expect(stats['presented'], greaterThan(0));
        });
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final env = await MetalViewportController.channel
              .invokeMapMethod<String, dynamic>('environment');
          expect(env!['activeRenderers'], 0);
        });
        size.dispose();
        camera.dispose();
        text.dispose();
      }
    },
  );
}
