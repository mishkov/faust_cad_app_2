import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
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
    position: Vertex(Vector3(0, -50, 100)),
    yaw: 0.35,
    pitch: -0.5,
    focalLength: 650.0,
    focusDistance: 200.0,
  );

  test('zoom leaves the original camera position unchanged', () {
    final originalPosition = camera.position.vector.clone();
    final zoomed = camera.zoomTowardCursor(
      cursor: viewport.center(Offset.zero),
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(camera.position.vector, originalPosition);
    expect(identical(zoomed.position, camera.position), isFalse);
    expect(zoomed.position.vector, isNot(originalPosition));
  });

  test('zoom keeps the ground point under the cursor', () {
    final target = Vertex(Vector3(20, 50, 0));
    final cursor = _project(target, camera, viewport);
    final zoomed = camera.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(zoomed.position.vector.z, lessThan(camera.position.vector.z));
    expect(_project(target, zoomed, viewport).dx, closeTo(cursor.dx, 1e-9));
    expect(_project(target, zoomed, viewport).dy, closeTo(cursor.dy, 1e-9));

    final restored = zoomed.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 0.8,
    );
    expect(restored.position.vector.x, closeTo(camera.position.vector.x, 1e-9));
    expect(restored.position.vector.y, closeTo(camera.position.vector.y, 1e-9));
    expect(restored.position.vector.z, closeTo(camera.position.vector.z, 1e-9));
  });

  test('zoom follows a ray toward a point above the ground', () {
    final target = Vertex(Vector3(0, 500, 120));
    final cursor = _project(target, camera, viewport);
    final zoomed = camera.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(cursor.dy, lessThan(viewport.height / 2));
    expect(zoomed.position.vector.z, greaterThan(camera.position.vector.z));
    expect(_project(target, zoomed, viewport).dx, closeTo(cursor.dx, 1e-9));
    expect(_project(target, zoomed, viewport).dy, closeTo(cursor.dy, 1e-9));

    final restored = zoomed.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 0.8,
    );
    expect(restored.position.vector.x, closeTo(camera.position.vector.x, 1e-9));
    expect(restored.position.vector.y, closeTo(camera.position.vector.y, 1e-9));
    expect(restored.position.vector.z, closeTo(camera.position.vector.z, 1e-9));
  });

  test('zoom works when the cursor ray is parallel to the ground', () {
    final levelCamera = camera.copyWith(pitch: 0);
    final zoomed = levelCamera.zoomTowardCursor(
      cursor: viewport.center(Offset.zero),
      viewport: viewport,
      scaleFactor: 1.25,
    );

    expect(
      zoomed.position.vector.y,
      greaterThan(levelCamera.position.vector.y),
    );
    expect(zoomed.position.vector.z, levelCamera.position.vector.z);
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
        before.position.vector.z +
        math.sin(before.pitch) * before.focusDistance * (1 - 1 / 1.5);
    expect(after.position.vector.z, closeTo(expectedZ, 1e-9));
    expect(after.focusDistance, closeTo(before.focusDistance / 1.5, 1e-9));
    expect(after.yaw, before.yaw);
    expect(after.pitch, before.pitch);

    await tester.sendEventToBinding(PointerPanZoomEndEvent(position: position));
  });

  for (final panDelta in [const Offset(20, 0), const Offset(0, 20)]) {
    final axis = panDelta.dx != 0 ? 'yaw' : 'pitch';
    testWidgets('$axis change restores zoom after repeated zooming', (
      tester,
    ) async {
      await tester.pumpWidget(const MainApp());
      final sceneBox = tester.renderObject<RenderBox>(find.byType(CadScene));
      final position = sceneBox.localToGlobal(
        sceneBox.size.center(Offset.zero),
      );
      final initial = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;

      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: position),
      );
      var scale = 1.0;
      for (var i = 0; i < 12; i++) {
        scale *= 5;
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: position, scale: scale),
        );
      }
      await tester.pump();
      final accumulated = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(accumulated.focusDistance, lessThan(1e-6));

      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          scale: scale,
          pan: panDelta,
          panDelta: panDelta,
        ),
      );
      await tester.pump();
      final rotated = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(rotated.focusDistance, initial.focusDistance);
      expect(rotated.position, accumulated.position);
      expect(rotated.yaw, initial.yaw - panDelta.dx * 0.005);
      expect(rotated.pitch, initial.pitch - panDelta.dy * 0.005);

      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          scale: scale * 1.25,
          pan: panDelta,
        ),
      );
      await tester.pump();
      final zoomed = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(zoomed.focusDistance, closeTo(initial.focusDistance / 1.25, 1e-9));
      expect(
        zoomed.position.vector.distanceTo(rotated.position.vector),
        closeTo(initial.focusDistance * (1 - 1 / 1.25), 1e-9),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: position),
      );
    });
  }

  testWidgets(
    'combined rotation and zoom preserves incremental gesture scale',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      final sceneBox = tester.renderObject<RenderBox>(find.byType(CadScene));
      final position = sceneBox.localToGlobal(
        sceneBox.size.center(Offset.zero),
      );
      final initial = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;

      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(position: position, scale: 1.2),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          scale: 1.5,
          pan: const Offset(20, 20),
          panDelta: const Offset(20, 20),
        ),
      );
      await tester.pump();
      final rotated = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(
        rotated.focusDistance,
        closeTo(initial.focusDistance / 1.25, 1e-9),
      );

      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          scale: 1.8,
          pan: const Offset(20, 20),
        ),
      );
      await tester.pump();
      final zoomed = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(zoomed.focusDistance, closeTo(initial.focusDistance / 1.5, 1e-9));
      expect(
        zoomed.position.vector.distanceTo(rotated.position.vector),
        closeTo(rotated.focusDistance * (1 - 1 / 1.2), 1e-9),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: position),
      );
    },
  );

  testWidgets(
    'new zoom gestures preserve depth while orientation is unchanged',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      final sceneBox = tester.renderObject<RenderBox>(find.byType(CadScene));
      final position = sceneBox.localToGlobal(
        sceneBox.size.center(Offset.zero),
      );
      final initial = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;

      for (var i = 0; i < 2; i++) {
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(position: position),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: position),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(position: position, scale: 1.25),
        );
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(position: position),
        );
      }
      await tester.pump();
      final zoomed = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(
        zoomed.focusDistance,
        closeTo(initial.focusDistance / (1.25 * 1.25), 1e-9),
      );
      expect(
        zoomed.position.vector.distanceTo(initial.position.vector),
        closeTo(initial.focusDistance * (1 - 1 / (1.25 * 1.25)), 1e-9),
      );
    },
  );
}

Offset _project(Vertex point, CameraConfig camera, Size viewport) {
  final dx = point.vector.x - camera.position.vector.x;
  final dy = point.vector.y - camera.position.vector.y;
  final dz = point.vector.z - camera.position.vector.z;
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
