import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, Object?>> viewportEnvironment() async {
  final values = await const MethodChannel('cad.benchmark.environment')
      .invokeMapMethod<String, Object?>('read');
  expect(
    values?['foreground'],
    true,
    reason: 'Benchmark window must be foreground',
  );
  expect(values?['session_available'], true);
  expect(
    values?['session_locked'],
    false,
    reason: 'Benchmark desktop must be unlocked',
  );
  expect(values?['on_console'], true);
  return values!;
}
