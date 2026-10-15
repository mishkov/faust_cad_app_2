import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/metal_performance_validation.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(() async {
    if (const bool.fromEnvironment('VIEWPORT_WAIT_FOR_FOCUS')) {
      final go = Completer<void>();
      developer.registerExtension('ext.cad.startBenchmark', (
        method,
        args,
      ) async {
        if (!go.isCompleted) go.complete();
        return developer.ServiceExtensionResponse.result('{}');
      });
      runApp(
        const MaterialApp(
          home: Scaffold(body: Text('Focus Metal performance')),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      debugPrintSynchronously('VIEWPORT_FOCUS_READY');
      await go.future.timeout(const Duration(minutes: 2));
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  });
  testWidgets('paired warmed Metal/Canvas cadence and optional soak', (
    tester,
  ) async {
    binding.reportData = await validateMetalPerformance(tester, binding);
  });
}
