import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/orbit_extrusion_fixture.dart';
import 'support/viewport_profile_painter.dart';
import '../test/cad_scene/rendering/viewport_image_comparison_test.dart'
    show compareViewportImages;

// Real engine frames: run with flutter drive --profile -d macos --enable-impeller.
// Warmup and capture use live vsync; no pump loop or PictureRecorder timing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(() async {
    if (const bool.fromEnvironment('VIEWPORT_WAIT_FOR_FOCUS')) {
      final ready = Completer<void>();
      developer.registerExtension('ext.cad.startBenchmark', (
        method,
        parameters,
      ) async {
        if (!ready.isCompleted) ready.complete();
        return developer.ServiceExtensionResponse.result('{}');
      });
      debugPrintSynchronously('VIEWPORT_FOCUS_READY');
      await ready.future.timeout(const Duration(minutes: 2));
      // Settle platform accessibility changes before the test captures invariants.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  });
  testWidgets('warmed desktop orbit, pan and zoom frame timings', (
    tester,
  ) async {
    final imageComparisons = const bool.fromEnvironment('VIEWPORT_CHECK_IMAGES')
        ? await tester.runAsync(compareViewportImages)
        : null;
    expect(tester.takeException(), isNull);
    Size? referenceSize;
    double? referenceDpr;
    final sketch = orbitSketch();
    final partial = orbitGeometry(sketch);
    final reports = <String, Object?>{};
    final activePainter = ValueNotifier<ViewportProfilePainter?>(null);
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
                    const Text('Viewport performance'),
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
                child: ValueListenableBuilder<ViewportProfilePainter?>(
                  valueListenable: activePainter,
                  builder: (context, painter, _) =>
                      CustomPaint(painter: painter),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Run every phase on the real clock. Returning to widget-test pumping
    // between captures can stall the desktop live-frame scheduler.
    await tester.runAsync(() async {
      for (final sceneName in ['default', 'partial_extrusion']) {
        final geometry = sceneName == 'default'
            ? partial.sublist(0, partial.length - 1)
            : partial;
        final scene = SceneTessellator().buildGeometry(geometry);
        for (final operation in ['orbit', 'pan', 'zoom']) {
          final modes = const bool.fromEnvironment('VIEWPORT_PAIRED')
              ? [true, false, false, true]
              : [const bool.fromEnvironment('VIEWPORT_BASELINE')];
          for (var run = 0; run < modes.length; run++) {
            final baseline = modes[run];
            final clock = ValueNotifier<double>(0);
            final painter = ViewportProfilePainter(
              clock,
              scene,
              sceneName == 'partial_extrusion' ? sketch : null,
              operation,
              baseline,
            );
            activePainter.value = painter;

            final timings = <ui.FrameTiming>[];
            var start = 0, end = 0;
            void onTimings(List<ui.FrameTiming> values) {
              timings.addAll(
                values.where((f) {
                  final t = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
                  return t >= start && (end == 0 || t <= end);
                }),
              );
            }

            final ticker = Ticker(
              (elapsed) => clock.value = elapsed.inMicroseconds / 1e6,
            );
            ticker.start();
            await Future<void>.delayed(const Duration(seconds: 6));
            start = developer.Timeline.now;
            binding.addTimingsCallback(onTimings);
            await Future<void>.delayed(const Duration(seconds: 6));
            end = developer.Timeline.now;
            ticker.stop();
            // Profile mode delivers timing batches; flush the last capture batch.
            await Future<void>.delayed(const Duration(seconds: 2));
            binding.removeTimingsCallback(onTimings);
            ticker.dispose();
            expect(timings.length, greaterThan(50));
            referenceSize ??= painter.size;
            referenceDpr ??=
                binding.platformDispatcher.views.first.devicePixelRatio;
            expect(painter.size, referenceSize);
            expect(
              binding.platformDispatcher.views.first.devicePixelRatio,
              referenceDpr,
            );
            reports['${sceneName}_${operation}_${baseline ? 'baseline' : 'optimized'}_$run'] =
                {
                  'baseline': baseline,
                  'scene': sceneName,
                  'operation': operation,
                  'frames': timings.length,
                  'capture_seconds': (end - start) / 1e6,
                  'frames_per_second': timings.length * 1e6 / (end - start),
                  'ui_ms': _summary(timings.map((f) => f.buildDuration)),
                  'raster_ms': _summary(timings.map((f) => f.rasterDuration)),
                  'either_over_16_7_ms_percent':
                      100 *
                      timings
                          .where(
                            (f) =>
                                f.buildDuration.inMicroseconds > 16700 ||
                                f.rasterDuration.inMicroseconds > 16700,
                          )
                          .length /
                      timings.length,
                  'layers': painter.layerSamples,
                  'viewport': [painter.size.width, painter.size.height],
                  'device_pixel_ratio':
                      binding.platformDispatcher.views.first.devicePixelRatio,
                  'raw_vsync_us': timings
                      .map(
                        (f) =>
                            f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
                      )
                      .toList(),
                  'raw_ui_us': timings
                      .map((f) => f.buildDuration.inMicroseconds)
                      .toList(),
                  'raw_raster_us': timings
                      .map((f) => f.rasterDuration.inMicroseconds)
                      .toList(),
                };
            debugPrintSynchronously(
              'VIEWPORT_RUN ${jsonEncode({'${sceneName}_${operation}_${baseline ? 'baseline' : 'optimized'}_$run': reports['${sceneName}_${operation}_${baseline ? 'baseline' : 'optimized'}_$run']})}',
            );
            debugPrint(
              '$sceneName $operation ${baseline ? 'baseline' : 'optimized'} run $run: ${timings.length} frames, '
              'UI ${_summary(timings.map((f) => f.buildDuration))}, '
              'raster ${_summary(timings.map((f) => f.rasterDuration))}',
            );
            expect(tester.takeException(), isNull);
            clock.dispose();
          }
        }
      }
    });
    expect(tester.takeException(), isNull);
    activePainter.dispose();
    binding.reportData = {
      'paired': const bool.fromEnvironment('VIEWPORT_PAIRED'),
      'image_comparisons': ?imageComparisons,
      'measurements': reports,
    };
  });
}

Map<String, double> _summary(Iterable<Duration> values) {
  final sorted = values.map((v) => v.inMicroseconds / 1000).toList()..sort();
  double percentile(double p) => sorted[(p * sorted.length).ceil() - 1];
  return {
    'p50': percentile(0.50),
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    'p95': percentile(0.95),
    'p99': percentile(0.99),
    'over_16_7_ms_percent':
        100 * sorted.where((v) => v > 16.7).length / sorted.length,
  };
}
