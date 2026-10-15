import 'dart:convert';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/orbit_extrusion_fixture.dart';
import 'support/viewport_profile_painter.dart';

// Run through tool/profile_viewport_memory.py. Its external VM client samples
// heap usage/capacity, requests GC, and records native vmmap summaries while the
// ticker is stopped. No GC or memory probe runs inside a frame-timing capture.
Completer<void>? _probeReady;

void main() {
  developer.registerExtension('ext.cad.memoryProbeComplete', (
    method,
    parameters,
  ) async {
    final ready = _probeReady;
    if (ready != null && !ready.isCompleted) ready.complete();
    return developer.ServiceExtensionResponse.result('{}');
  });
  const cycles = int.fromEnvironment('MEMORY_CYCLES', defaultValue: 10);
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('identical orbit cycles reach a bounded memory plateau', (
    tester,
  ) async {
    final sketch = orbitSketch();
    final geometry = orbitGeometry(sketch);
    final clock = ValueNotifier<double>(0);
    final activePainter = ValueNotifier<ViewportProfilePainter?>(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 240, child: Text('Viewport memory')),
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
    await tester.runAsync(() async {
      await _sampleMemory('blank', 'idle', 0);
      for (final partial in [false, true]) {
        final scene = SceneTessellator().buildGeometry(
          partial ? geometry : geometry.sublist(0, geometry.length - 1),
        );
        final painter = ViewportProfilePainter(
          clock,
          scene,
          partial ? sketch : null,
          'orbit',
          const bool.fromEnvironment('VIEWPORT_BASELINE'),
        );
        activePainter.value = painter;
        Future<void> sample(String phase, int cycle) => _sampleMemory(
          partial ? 'partial_extrusion' : 'default',
          phase,
          cycle,
          painter: painter,
        );

        await Future<void>.delayed(const Duration(seconds: 2));
        await sample('idle', 0);
        for (var cycle = 1; cycle <= cycles; cycle++) {
          final before = painter.paintCount;
          final ticker = Ticker(
            (elapsed) => clock.value = elapsed.inMicroseconds / 1e6,
          )..start();
          await Future<void>.delayed(const Duration(seconds: 6));
          ticker.stop();
          ticker.dispose();
          expect(painter.paintCount - before, greaterThan(20));
          await sample('rotation', cycle);
          painter.layerSamples.clear();
        }
        await Future<void>.delayed(const Duration(seconds: 10));
        await sample('rest', cycles);
      }
      activePainter.value = null;
      await Future<void>.delayed(const Duration(seconds: 10));
      await _sampleMemory('unmounted', 'rest', cycles);
    });
    await tester.pumpWidget(const SizedBox());
    clock.dispose();
    activePainter.dispose();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _sampleMemory(
  String scene,
  String phase,
  int cycle, {
  ViewportProfilePainter? painter,
}) async {
  if (painter != null) {
    expect(painter.size.isEmpty, false);
    expect(painter.paintCount, greaterThan(0));
  }
  _probeReady = Completer<void>();
  debugPrintSynchronously(
    'MEMORY_SAMPLE ${jsonEncode({
      'scene': scene,
      'phase': phase,
      'cycle': cycle,
      'rss': ProcessInfo.currentRss,
      'max_rss': ProcessInfo.maxRss,
      'paints': painter?.paintCount,
      'viewport': painter == null ? null : [painter.size.width, painter.size.height],
      'dpr': WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio,
    })}',
  );
  try {
    await _probeReady!.future.timeout(const Duration(seconds: 30));
  } finally {
    _probeReady = null;
  }
}
