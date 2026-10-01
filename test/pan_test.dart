import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/main_app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  for (final orientation in [(0.0, 0.0), (0.7, -0.5), (-1.2, math.pi / 2)]) {
    final camera = CameraConfig(
      position: Vertex(Vector3(10, -50, 100)),
      yaw: orientation.$1,
      pitch: orientation.$2,
      focalLength: 500,
      focusDistance: 200,
    );
    for (final delta in [
      const Offset(20, 0),
      const Offset(-20, 0),
      const Offset(0, 20),
      const Offset(0, -20),
    ]) {
      test('pan $delta preserves the view plane at $orientation', () {
        final originalPosition = camera.position.vector.clone();
        final panned = camera.pan(delta);
        final translation = panned.position.vector - originalPosition;

        // Transform back into camera space: no movement along the view ray.
        final x =
            translation.x * math.cos(camera.yaw) +
            translation.y * math.sin(camera.yaw);
        final y =
            -translation.x * math.sin(camera.yaw) +
            translation.y * math.cos(camera.yaw);
        final depth =
            y * math.cos(camera.pitch) + translation.z * math.sin(camera.pitch);
        final z =
            -y * math.sin(camera.pitch) +
            translation.z * math.cos(camera.pitch);

        // A point at focus depth follows the fingers by exactly delta pixels.
        expect(
          -x / camera.focusDistance * camera.focalLength,
          closeTo(delta.dx, 1e-9),
        );
        expect(
          z / camera.focusDistance * camera.focalLength,
          closeTo(delta.dy, 1e-9),
        );
        expect(depth, closeTo(0, 1e-9));
        expect(panned.yaw, camera.yaw);
        expect(panned.pitch, camera.pitch);
        expect(panned.focalLength, camera.focalLength);
        expect(panned.focusDistance, camera.focusDistance);
        expect(camera.position.vector, originalPosition);
      });
    }
  }

  for (final shiftKey in [
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  ]) {
    testWidgets(
      '$shiftKey switches between rotation and pan during a gesture',
      (tester) async {
        await tester.pumpWidget(const MainApp());
        final sceneBox = tester.renderObject<RenderBox>(find.byType(CadScene));
        final position = sceneBox.localToGlobal(
          sceneBox.size.center(Offset.zero),
        );
        CameraConfig camera() =>
            tester.widget<CadScene>(find.byType(CadScene)).cameraConfig;

        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: position),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: position, scale: 2),
        );
        await tester.pump();
        final zoomed = camera();

        await tester.sendKeyDownEvent(shiftKey);
        const delta = Offset(25, -15);
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: position,
            scale: 2,
            pan: delta,
            panDelta: delta,
          ),
        );
        await tester.pump();
        final panned = camera();
        expect(
          panned.position.vector.distanceTo(zoomed.position.vector),
          closeTo(
            delta.distance * zoomed.focusDistance / zoomed.focalLength,
            1e-9,
          ),
        );
        expect(panned.yaw, zoomed.yaw);
        expect(panned.pitch, zoomed.pitch);
        expect(panned.focusDistance, zoomed.focusDistance);

        // Pinching still uses incremental scale while Shift is held.
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: position, scale: 2.5, pan: delta),
        );
        await tester.pump();
        final pinched = camera();
        expect(
          pinched.focusDistance,
          closeTo(panned.focusDistance / 1.25, 1e-9),
        );
        expect(
          pinched.position.vector.distanceTo(panned.position.vector),
          closeTo(panned.focusDistance * (1 - 1 / 1.25), 1e-9),
        );
        expect(pinched.yaw, panned.yaw);
        expect(pinched.pitch, panned.pitch);

        await tester.sendKeyUpEvent(shiftKey);
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            position: position,
            scale: 2.5,
            pan: delta * 2,
            panDelta: delta,
          ),
        );
        await tester.pump();
        final rotated = camera();
        expect(rotated.position.vector, pinched.position.vector);
        expect(rotated.yaw, pinched.yaw - delta.dx * 0.005);
        expect(rotated.pitch, pinched.pitch - delta.dy * 0.005);
        expect(rotated.focusDistance, 200);
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: position),
        );
      },
    );
  }
}
