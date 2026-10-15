import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

Future<void> waitForViewportFocus() async {
  if (!const bool.fromEnvironment('VIEWPORT_WAIT_FOR_FOCUS')) return;
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
  await Future<void>.delayed(const Duration(seconds: 1));
}
