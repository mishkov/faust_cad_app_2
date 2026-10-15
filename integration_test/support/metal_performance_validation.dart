import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../test/support/orbit_extrusion_fixture.dart';
import 'viewport_profile_painter.dart';

Map<String, double> percentiles(Iterable<double> values) {
  final a = values.toList()..sort();
  if (a.isEmpty) return {};
  double at(double p) => a[(p * a.length).ceil() - 1];
  return {'p50': at(.5), 'p95': at(.95), 'p99': at(.99)};
}

Future<Map<String, dynamic>> validateMetalPerformance(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  final reports = <String, dynamic>{};
  final sketch = orbitSketch(), partial = orbitGeometry(orbitSketch());
  for (final name in ['default', 'partial']) {
    final geometry = name == 'default'
        ? partial.sublist(0, partial.length - 1)
        : partial;
    final scene = SceneTessellator().buildGeometry(geometry);
    for (final backend in CadRenderBackend.values) {
      final controller = MetalViewportController();
      final clock = ValueNotifier<double>(0);
      var operation = 'orbit';
      Size viewport = Size.zero;
      final dpr = binding.platformDispatcher.views.first.devicePixelRatio;
      ViewportProfilePainter? painter;
      final operationRevision = ValueNotifier<int>(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 240,
                  child: Column(
                    children: [
                      Text('Viewport performance: $name ${backend.name}'),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('New sketch'),
                      ),
                      const TextField(
                        decoration: InputDecoration(labelText: 'Distance'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      viewport = constraints.biggest;
                      return ValueListenableBuilder<int>(
                        valueListenable: operationRevision,
                        builder: (context, _, _) {
                          if (backend == CadRenderBackend.canvas) {
                            painter = ViewportProfilePainter(
                              clock,
                              scene,
                              name == 'partial' ? sketch : null,
                              operation,
                              false,
                            );
                            return CustomPaint(painter: painter);
                          }
                          return ValueListenableBuilder<double>(
                            valueListenable: clock,
                            builder: (context, seconds, _) {
                              final t = seconds * math.pi / 3;
                              final yaw = operation == 'orbit'
                                  ? -.9 + math.sin(t) * .8
                                  : -.9;
                              final pitch = operation == 'orbit'
                                  ? -.5 + math.sin(t * 2) * .65
                                  : -.5;
                              final forward = Vector3(
                                -math.sin(yaw) * math.cos(pitch),
                                math.cos(yaw) * math.cos(pitch),
                                math.sin(pitch),
                              );
                              var camera = CameraConfig(
                                position: Vertex(
                                  Vector3(35, 25, 5) - forward * 220,
                                ),
                                yaw: yaw,
                                pitch: pitch,
                                focalLength: 500,
                                focusDistance: 220,
                              );
                              if (operation == 'pan') {
                                camera = camera.pan(
                                  Offset(60 * math.sin(t), 40 * math.cos(t)),
                                );
                              }
                              if (operation == 'zoom') {
                                camera = camera.zoomTowardCursor(
                                  cursor: viewport.center(Offset.zero),
                                  viewport: viewport,
                                  scaleFactor: 1 + .3 * math.sin(t),
                                );
                              }
                              return CadScene(
                                backend: backend,
                                metalController: controller,
                                cameraConfig: camera,
                                geometry: geometry,
                                renderMode: CadRenderMode.shaded,
                                sketches: name == 'partial'
                                    ? [sketch]
                                    : const [],
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final runningTickers = <Ticker>{};
      try {
        await tester.runAsync(() async {
          if (backend == CadRenderBackend.metal) {
            expect(await controller.ready, greaterThan(0));
          }
          for (final op in ['orbit', 'pan', 'zoom']) {
            debugPrintSynchronously(
              'METAL_PHASE ${name}_${backend.name}_$op warm',
            );
            operation = op;
            operationRevision.value++;
            final ticker = Ticker(
              (elapsed) => clock.value = elapsed.inMicroseconds / 1e6,
            )..start();
            runningTickers.add(ticker);
            await Future<void>.delayed(const Duration(seconds: 4));
            debugPrintSynchronously(
              'METAL_PHASE ${name}_${backend.name}_$op capture',
            );
            final environment = await MetalViewportController.channel
                .invokeMapMethod<String, dynamic>('environment')
                .timeout(const Duration(seconds: 5));
            expect(environment!['foregroundPid'], environment['pid']);
            expect(environment['desktopUnlocked'], isTrue);
            final before = backend == CadRenderBackend.metal
                ? await controller.stats()
                : null;
            final nativeStart = backend == CadRenderBackend.metal
                ? await controller.resetMetrics()
                : null;
            final frames = <ui.FrameTiming>[];
            var start = developer.Timeline.now, end = 0;
            void onTimings(List<ui.FrameTiming> batch) {
              frames.addAll(
                batch.where((f) {
                  final time = f.timestampInMicroseconds(
                    ui.FramePhase.vsyncStart,
                  );
                  return time >= start && (end == 0 || time <= end);
                }),
              );
            }

            binding.addTimingsCallback(onTimings);
            await Future<void>.delayed(const Duration(seconds: 6));
            end = developer.Timeline.now;
            ticker.stop();
            final nativeEnd = backend == CadRenderBackend.metal
                ? (await controller.stats())['nativeTime'] as num
                : null;
            await Future<void>.delayed(const Duration(seconds: 1));
            binding.removeTimingsCallback(onTimings);
            ticker.dispose();
            runningTickers.remove(ticker);
            final after = backend == CadRenderBackend.metal
                ? await controller.stats()
                : null;
            final seconds = (end - start) / 1e6;
            final timestamps =
                (after?['presentedAtSeconds'] as List?)?.cast<num>() ?? [];
            final capturedTimes = [
              for (final t in timestamps)
                if (t >= nativeStart! && t <= nativeEnd!) t,
            ];
            final record = {
              'environment': environment,
              'viewport': [viewport.width, viewport.height],
              'dpr': dpr,
              'seconds': seconds,
              'flutterFrames': frames.length,
              'flutterFps': frames.length / seconds,
              'uiMs': percentiles(
                frames.map((f) => f.buildDuration.inMicroseconds / 1000),
              ),
              'rasterMs': percentiles(
                frames.map((f) => f.rasterDuration.inMicroseconds / 1000),
              ),
              if (after != null) ...{
                'deliveredFps':
                    capturedTimes.length / (nativeEnd! - nativeStart!),
                'deliveredFrames': capturedTimes.length,
                'nativeCaptureSeconds': nativeEnd - nativeStart,
                'gpuMs': percentiles(
                  (after['gpuMilliseconds'] as List).cast<num>().map(
                    (n) => n.toDouble(),
                  ),
                ),
                'nativeRequestToPresentMs': percentiles(
                  (after['requestToPresentMilliseconds'] as List)
                      .cast<num>()
                      .map((n) => n.toDouble()),
                ),
                'presentIntervalMs': percentiles([
                  for (var i = 1; i < capturedTimes.length; i++)
                    (capturedTimes[i] - capturedTimes[i - 1]) * 1000,
                ]),
                'before': before,
                'after': after,
              },
            };
            reports['${name}_${backend.name}_$op'] = record;
            debugPrint(
              'METAL_BENCH ${name}_${backend.name}_$op: ${record['flutterFps']} Flutter FPS ${record['deliveredFps']} presented FPS',
            );
            expect(frames.length, greaterThan(50));
            if (after != null) {
              expect(after['error'], isNull);
              expect(after['presented'], greaterThan(50));
              expect(after['peakInFlight'], lessThanOrEqualTo(2));
            }
          }
          if (backend == CadRenderBackend.metal &&
              name == 'partial' &&
              const bool.fromEnvironment('METAL_SOAK')) {
            operation = 'orbit';
            operationRevision.value++;
            final before = await controller.stats(),
                samples = <Map<String, dynamic>>[];
            final ticker = Ticker(
              (elapsed) => clock.value = elapsed.inMicroseconds / 1e6,
            )..start();
            runningTickers.add(ticker);
            for (var i = 0; i < 6; i++) {
              await Future<void>.delayed(const Duration(seconds: 30));
              final stats = await controller.stats();
              expect(stats['error'], isNull);
              expect(
                stats['presented'],
                greaterThan((before['presented'] as int) + 1000),
              );
              samples.add(stats);
              debugPrint(
                'METAL_SOAK ${(i + 1) * 30}s: ${stats['presented']} presented',
              );
            }
            ticker.stop();
            ticker.dispose();
            runningTickers.remove(ticker);
            reports['soak'] = {'before': before, 'samples': samples};
          }
        });
      } finally {
        for (final ticker in runningTickers) {
          ticker.dispose();
        }
      }
      final error = tester.takeException();
      if (error != null) throw error;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      if (backend == CadRenderBackend.canvas) controller.dispose();
      clock.dispose();
      operationRevision.dispose();
    }
  }
  return {'performance': reports};
}
