import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/main_app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  const viewport = Size(1000, 800);
  final camera = CameraConfig(
    position: Vector3(0, -50, 100),
    yaw: 0.35,
    pitch: -0.5,
    focalLength: 650.0,
    focusDistance: 200.0,
  );

  test('zoom leaves the original camera position unchanged', () {
    final originalPosition = camera.position.clone();
    final zoomed = camera.zoomTowardCursor(
      cursor: viewport.center(Offset.zero),
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(camera.position, originalPosition);
    expect(identical(zoomed.position, camera.position), isFalse);
    expect(zoomed.position, isNot(originalPosition));
  });

  test('zoom keeps the ground point under the cursor', () {
    final target = Vector3(20, 50, 0);
    final cursor = _project(target, camera, viewport);
    final zoomed = camera.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(zoomed.position.z, lessThan(camera.position.z));
    expect(_project(target, zoomed, viewport).dx, closeTo(cursor.dx, 1e-9));
    expect(_project(target, zoomed, viewport).dy, closeTo(cursor.dy, 1e-9));

    final restored = zoomed.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 0.8,
    );
    expect(restored.position.x, closeTo(camera.position.x, 1e-9));
    expect(restored.position.y, closeTo(camera.position.y, 1e-9));
    expect(restored.position.z, closeTo(camera.position.z, 1e-9));
  });

  test('zoom follows a ray toward a point above the ground', () {
    final target = Vector3(0, 500, 120);
    final cursor = _project(target, camera, viewport);
    final zoomed = camera.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(cursor.dy, lessThan(viewport.height / 2));
    expect(zoomed.position.z, greaterThan(camera.position.z));
    expect(_project(target, zoomed, viewport).dx, closeTo(cursor.dx, 1e-9));
    expect(_project(target, zoomed, viewport).dy, closeTo(cursor.dy, 1e-9));

    final restored = zoomed.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 0.8,
    );
    expect(restored.position.x, closeTo(camera.position.x, 1e-9));
    expect(restored.position.y, closeTo(camera.position.y, 1e-9));
    expect(restored.position.z, closeTo(camera.position.z, 1e-9));
  });

  test('zoom works when the cursor ray is parallel to the ground', () {
    final levelCamera = camera.copyWith(pitch: 0);
    final zoomed = levelCamera.zoomTowardCursor(
      cursor: viewport.center(Offset.zero),
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(zoomed.position.y, greaterThan(levelCamera.position.y));
    expect(zoomed.position.z, levelCamera.position.z);
  });

  testWidgets('pan zoom uses incremental scale from cumulative updates', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    final sceneBox = tester.renderObject<RenderBox>(find.byType(CadScene));
    final before = tester.widget<CadScene>(find.byType(CadScene)).cameraConfig;
    final position = sceneBox.localToGlobal(sceneBox.size.center(Offset.zero));

    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(position: position),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(position: position, scale: 1.2),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(position: position, scale: 1.5),
    );
    await tester.pump();

    final after = tester.widget<CadScene>(find.byType(CadScene)).cameraConfig;
    final expectedZ =
        before.position.z +
        math.sin(before.pitch) * before.focusDistance * (1 - 1 / 1.5);
    expect(after.position.z, closeTo(expectedZ, 1e-9));
    expect(after.focusDistance, closeTo(before.focusDistance / 1.5, 1e-9));
    expect(after.yaw, before.yaw);
    expect(after.pitch, before.pitch);

    await tester.sendEventToBinding(PointerPanZoomEndEvent(position: position));
  });
}

Offset _project(Vector3 point, CameraConfig camera, Size viewport) {
  final dx = point.x - camera.position.x;
  final dy = point.y - camera.position.y;
  final dz = point.z - camera.position.z;
  final cy = math.cos(-camera.yaw);
  final sy = math.sin(-camera.yaw);
  final x = dx * cy - dy * sy;
  final y = dx * sy + dy * cy;
  final cp = math.cos(-camera.pitch);
  final sp = math.sin(-camera.pitch);
  final cameraY = y * cp - dz * sp;
  final cameraZ = y * sp + dz * cp;
  return Offset(
    viewport.width / 2 + x / cameraY * camera.focalLength,
    viewport.height / 2 - cameraZ / cameraY * camera.focalLength,
  );
}
