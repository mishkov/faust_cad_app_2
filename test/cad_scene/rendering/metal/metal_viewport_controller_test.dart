import 'dart:async';

import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'coalesces pending cameras while preserving a new geometry revision',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final firstAck = Completer<void>(),
          firstSent = Completer<void>(),
          secondSent = Completer<void>();
      final updates = <Map<Object?, Object?>>[];
      var creates = 0, disposes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MetalViewportController.channel, (
            call,
          ) async {
            if (call.method == 'create') {
              creates++;
              return 7;
            }
            if (call.method == 'dispose') {
              disposes++;
              return null;
            }
            if (call.method == 'update') {
              updates.add(Map<Object?, Object?>.from(call.arguments as Map));
              if (updates.length == 1) {
                firstSent.complete();
                await firstAck.future;
              } else {
                secondSent.complete();
              }
            }
            return null;
          });
      final controller = MetalViewportController();
      try {
        controller.update({
          'camera': Float64List.fromList([0]),
          'mesh': {'revision': 1},
        });
        await controller.initialize();
        await controller.initialize();
        await firstSent.future;
        controller.update({
          'camera': Float64List.fromList([1]),
          'mesh': {'revision': 2},
        });
        for (var i = 2; i <= 100; i++) {
          controller.update({
            'camera': Float64List.fromList([i.toDouble()]),
          });
        }
        expect(updates.length, 1);
        firstAck.complete();
        await secondSent.future;
        expect(updates.length, 2);
        expect((updates.last['mesh'] as Map)['revision'], 2);
        expect((updates.last['camera'] as Float64List).single, 100);
        expect(creates, 1);
        controller.dispose();
        controller.dispose();
        await Future<void>.delayed(Duration.zero);
        expect(disposes, 1);
      } finally {
        controller.dispose();
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MetalViewportController.channel, null);
      }
    },
  );
}
