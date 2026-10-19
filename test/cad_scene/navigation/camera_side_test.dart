import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/camera_side.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  final camera = CameraConfig(
    position: Vertex(Vector3(0, -10, 5)),
    yaw: 0,
    pitch: -.3,
    focalLength: 500,
    focusDistance: 20,
  );
  for (final side in CameraSide.values) {
    test(
      '${side.name} centers all bounds, preserves zoom and clears every point',
      () {
        final points = [
          for (final x in [-3000.0, 50.0])
            for (final y in [-600.0, 10000.0])
              for (final z in [-12000.0, 90.0]) Vector3(x, y, z),
        ];
        final target = side.cameraFor(camera, points);
        final projection = CameraProjection(target);
        expect(target.isOrthographic, isTrue);
        expect(target.focusDistance, camera.focusDistance);
        expect(target.focalLength, camera.focalLength);
        for (final point in points) {
          expect(projection.toCameraSpace(point).y, greaterThan(1));
        }
        final center = projection.toCameraSpace(
          (points.first + points.last) / 2,
        );
        expect(center.x.abs(), lessThan(1e-8));
        expect(center.z.abs(), lessThan(1e-8));
        expect(
          projection.toCameraDirection(-side.outward).y,
          closeTo(1, 1e-12),
        );
        // Objects are allowed to remain outside the viewport at the current zoom.
        expect(
          points.map(projection.toCameraSpace).any((p) => p.x.abs() > 100),
          isTrue,
        );
      },
    );
  }

  test('empty scenes and orthographic cursor zoom remain finite', () {
    final target = CameraSide.top.cameraFor(camera, []);
    expect(target.position.vector.length.isFinite, isTrue);
    final projection = CameraProjection(target);
    const viewport = Size(600, 400), cursor = Offset(420, 270);
    final underCursor =
        target.position.vector +
        projection.fromCameraDirection(
          Vector3(120 / 500 * 20, 50, -70 / 500 * 20),
        );
    final zoomed = target.zoomTowardCursor(
      cursor: cursor,
      viewport: viewport,
      scaleFactor: 2,
    );
    final zoomProjection = CameraProjection(zoomed);
    final screen = zoomProjection.project(
      zoomProjection.toCameraSpace(underCursor),
      screen: viewport,
    );
    expect(screen.x, closeTo(cursor.dx, 1e-9));
    expect(screen.y, closeTo(cursor.dy, 1e-9));
    expect(zoomed.isOrthographic, isTrue);
    expect(zoomed.focusDistance, 10);
  });
}
