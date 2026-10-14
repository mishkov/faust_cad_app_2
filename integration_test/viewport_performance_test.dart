import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../test/support/orbit_extrusion_fixture.dart';
import '../test/support/baseline_shaded_scene_renderer.dart';

// Real engine frames: run with flutter drive --profile -d macos --enable-impeller.
// Warmup and capture use live vsync; no pump loop or PictureRecorder timing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('warmed desktop orbit, pan and zoom frame timings', (
    tester,
  ) async {
    final sketch = orbitSketch();
    final partial = orbitGeometry(sketch);
    final reports = <String, Object?>{};
    final activePainter = ValueNotifier<_ViewportPainter?>(null);
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
                child: ValueListenableBuilder<_ViewportPainter?>(
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
            final painter = _ViewportPainter(
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
      'measurements': reports,
    };
  });
}

Map<String, double> _summary(Iterable<Duration> values) {
  final sorted = values.map((v) => v.inMicroseconds / 1000).toList()..sort();
  double percentile(double p) => sorted[(p * sorted.length).ceil() - 1];
  return {
    'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    'p95': percentile(0.95),
    'p99': percentile(0.99),
    'over_16_7_ms_percent':
        100 * sorted.where((v) => v > 16.7).length / sorted.length,
  };
}

class _ViewportPainter extends CustomPainter {
  _ViewportPainter(
    this.clock,
    this.scene,
    this.sketch,
    this.operation,
    this.baseline,
  ) : super(repaint: clock);
  final ValueNotifier<double> clock;
  final TessellatedScene scene;
  final SketchGeometry? sketch;
  final String operation;
  final bool baseline;
  Size size = Size.zero;
  final layerSamples = <Map<String, int>>[];
  int _paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    this.size = size;
    final t = clock.value * math.pi / 3;
    final yaw = operation == 'orbit' ? -0.9 + math.sin(t) * 0.8 : -0.9;
    final pitch = operation == 'orbit' ? -0.5 + math.sin(t * 2) * 0.65 : -0.5;
    final forward = Vector3(
      -math.sin(yaw) * math.cos(pitch),
      math.cos(yaw) * math.cos(pitch),
      math.sin(pitch),
    );
    var camera = CameraConfig(
      position: Vertex(Vector3(35, 25, 5) - forward * 220),
      yaw: yaw,
      pitch: pitch,
      focalLength: 500,
      focusDistance: 220,
    );
    if (operation == 'pan') {
      camera = camera.pan(Offset(60 * math.sin(t), 40 * math.cos(t)));
    }
    if (operation == 'zoom') {
      camera = camera.zoomTowardCursor(
        cursor: size.center(Offset.zero),
        viewport: size,
        scaleFactor: 1 + 0.3 * math.sin(t),
      );
    }
    // Count only one in thirty frames to keep instrumentation off the hot path.
    final layers = _paints++ % 30 == 0 ? ViewportLayerCounts() : null;
    if (baseline) {
      BaselineShadedSceneRenderer(
        camera,
        layerCounts: layers,
      ).paint(canvas, size, scene);
    } else {
      ShadedSceneRenderer(
        camera,
        layerCounts: layers,
      ).paint(canvas, size, scene);
    }
    if (sketch != null) {
      SketchScenePainter(
        sketches: [sketch!],
        camera: camera,
        occluders: scene,
        layerCounts: layers,
      ).paint(canvas, size);
    }
    if (layers != null) layerSamples.add(layers.toJson());
  }

  @override
  bool shouldRepaint(_ViewportPainter oldDelegate) => true;
}
