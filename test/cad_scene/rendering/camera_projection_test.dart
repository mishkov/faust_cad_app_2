import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('orthographic size and side clipping do not depend on depth', () {
    final config = CameraConfig(
      position: Vertex(Vector3.zero()),
      yaw: 0,
      pitch: 0,
      focalLength: 100,
      focusDistance: 10,
      isOrthographic: true,
    );
    final projection = CameraProjection(config);
    const screen = Size(200, 100);
    for (final depth in [0.001, 2.0, 10000.0]) {
      final point = Vector3(3, depth, 2);
      expect(projection.project(point, screen: screen), (x: 130.0, y: 30.0));
      final clipped = projection.clipLine(
        Vector3(-20, depth, 0),
        Vector3(20, depth, 0),
        screen: screen,
      )!;
      expect(clipped.begin.x, closeTo(-10, 1e-9));
      expect(clipped.end.x, closeTo(10, 1e-9));
      expect(
        projection.clipLoop([
          Vector3(-20, depth, -20),
          Vector3(20, depth, -20),
          Vector3(20, depth, 20),
          Vector3(-20, depth, 20),
        ], screen: screen),
        hasLength(4),
      );
    }
    expect(
      projection.clipLine(
        Vector3(0, -10, 0),
        Vector3(1, -2, 0),
        screen: screen,
      ),
      isNull,
    );
  });

  CameraConfig camera({double yaw = 0, double pitch = 0}) => CameraConfig(
    position: Vertex(Vector3(3, -7, 2)),
    yaw: yaw,
    pitch: pitch,
    focalLength: 100,
    focusDistance: 10,
  );

  test('cached rotation preserves camera axes and its inverse', () {
    final yaw = CameraProjection(camera(yaw: math.pi / 2));
    expect(
      (yaw.toCameraDirection(Vector3(1, 0, 0)) - Vector3(0, -1, 0)).length,
      lessThan(1e-12),
    );
    final pitch = CameraProjection(camera(pitch: math.pi / 2));
    expect(
      (pitch.toCameraDirection(Vector3(0, 0, 1)) - Vector3(0, 1, 0)).length,
      lessThan(1e-12),
    );
    for (final yaw in [-2.1, 0.0, 0.7]) {
      for (final pitch in [-0.8, 0.0, 1.2]) {
        final config = camera(yaw: yaw, pitch: pitch);
        final projection = CameraProjection(config);
        final point = Vector3(17, -31, 9);
        final rotated = projection.toCameraDirection(point);
        expect(rotated.length, closeTo(point.length, 1e-12));
        expect(
          (projection.fromCameraDirection(rotated) - point).length,
          lessThan(1e-12),
        );
        expect(point, Vector3(17, -31, 9));
        expect(
          projection.toCameraSpace(config.position.vector),
          Vector3.zero(),
        );
      }
    }
  });

  test('cached clipping planes follow viewport resize for lines and loops', () {
    final projection = CameraProjection(camera());
    final begin = Vector3(-4, 2, 0), end = Vector3(4, 2, 0);
    final loop = [
      Vector3(-4, 2, -4),
      Vector3(4, 2, -4),
      Vector3(4, 2, 4),
      Vector3(-4, 2, 4),
    ];
    for (final screen in [
      const Size(100, 100),
      const Size(300, 200),
      const Size(100, 100),
    ]) {
      final expectedX = screen.width / 100;
      final clipped = projection.clipLine(begin, end, screen: screen)!;
      expect(clipped.begin.x, closeTo(-expectedX, 1e-12));
      expect(clipped.end.x, closeTo(expectedX, 1e-12));
      final polygon = projection.clipLoop(loop, screen: screen);
      expect(polygon, hasLength(4));
      for (final point in polygon) {
        expect(point.x.abs(), closeTo(expectedX, 1e-12));
        expect(point.z.abs(), closeTo(screen.height / 100, 1e-12));
      }
    }
    expect(begin, Vector3(-4, 2, 0));
    expect(end, Vector3(4, 2, 0));
  });
}
