import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/main_app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final commandKey in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  ]) {
    testWidgets('$commandKey + 1 animates back to the initial view', (
      tester,
    ) async {
      await tester.pumpWidget(const MainApp());
      await tester.pump();
      final initial = _camera(tester);
      await _moveCamera(tester);
      final moved = _camera(tester);
      expect(moved.position.vector, isNot(initial.position.vector));
      expect(moved.yaw, isNot(initial.yaw));
      expect(moved.pitch, isNot(initial.pitch));
      expect(moved.focusDistance, isNot(initial.focusDistance));

      await _resetCamera(tester, commandKey);
      await tester.pump();
      _expectSameCamera(_camera(tester), moved);

      await tester.pump(const Duration(milliseconds: 175));
      final halfway = _camera(tester);
      final initialDistance = moved.position.vector.distanceTo(
        initial.position.vector,
      );
      expect(
        halfway.position.vector.distanceTo(initial.position.vector),
        closeTo(initialDistance / 2, 1e-6),
      );
      expect(halfway.yaw, closeTo((moved.yaw + initial.yaw) / 2, 1e-6));
      expect(halfway.pitch, closeTo((moved.pitch + initial.pitch) / 2, 1e-6));
      expect(
        halfway.focusDistance,
        closeTo((moved.focusDistance + initial.focusDistance) / 2, 1e-6),
      );

      await tester.pumpAndSettle();
      _expectSameCamera(_camera(tester), initial);
    });
  }

  testWidgets('1 alone and Control+1 leave the camera unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();
    await _moveCamera(tester);
    final moved = _camera(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pumpAndSettle();
    _expectSameCamera(_camera(tester), moved);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    _expectSameCamera(_camera(tester), moved);
  });

  testWidgets('restarting a reset continues from the current camera', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();
    final initial = _camera(tester);
    await _moveCamera(tester);
    await _resetCamera(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final intermediate = _camera(tester);

    await _resetCamera(tester);
    await tester.pump();
    _expectSameCamera(_camera(tester), intermediate);
    await tester.pumpAndSettle();
    _expectSameCamera(_camera(tester), initial);
  });

  testWidgets('a camera gesture interrupts the reset animation', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();
    await _moveCamera(tester);
    await _resetCamera(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final intermediate = _camera(tester);
    final position = tester.getCenter(find.byType(CadScene));

    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(position: position),
    );
    const delta = Offset(20, 10);
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        position: position,
        pan: delta,
        panDelta: delta,
      ),
    );
    await tester.sendEventToBinding(PointerPanZoomEndEvent(position: position));
    await tester.pump();
    final interrupted = _camera(tester);
    expect(interrupted.position.vector, intermediate.position.vector);
    expect(interrupted.yaw, intermediate.yaw - delta.dx * 0.005);
    expect(interrupted.pitch, intermediate.pitch - delta.dy * 0.005);

    await tester.pump(const Duration(seconds: 1));
    _expectSameCamera(_camera(tester), interrupted);
  });

  testWidgets('disposing the screen cancels an active reset', (tester) async {
    await tester.pumpWidget(const MainApp());
    await tester.pump();
    await _moveCamera(tester);
    await _resetCamera(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

CameraConfig _camera(WidgetTester tester) =>
    tester.widget<CadScene>(find.byType(CadScene)).cameraConfig;

void _expectSameCamera(CameraConfig actual, CameraConfig expected) {
  expect(actual.position.vector, expected.position.vector);
  expect(actual.yaw, expected.yaw);
  expect(actual.pitch, expected.pitch);
  expect(actual.focalLength, expected.focalLength);
  expect(actual.focusDistance, expected.focusDistance);
}

Future<void> _moveCamera(WidgetTester tester) async {
  final position = tester.getCenter(find.byType(CadScene));
  await tester.sendEventToBinding(PointerPanZoomStartEvent(position: position));
  const delta = Offset(40, -20);
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      position: position,
      pan: delta,
      panDelta: delta,
      scale: 2,
    ),
  );
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      position: position,
      pan: delta * 2,
      panDelta: delta,
      scale: 2,
    ),
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendEventToBinding(PointerPanZoomEndEvent(position: position));
  await tester.pump();
}

Future<void> _resetCamera(
  WidgetTester tester, [
  LogicalKeyboardKey commandKey = LogicalKeyboardKey.metaLeft,
]) async {
  await tester.sendKeyDownEvent(commandKey);
  await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
  await tester.sendKeyUpEvent(commandKey);
}
