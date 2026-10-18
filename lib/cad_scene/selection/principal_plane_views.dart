import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../../document/planar_support.dart';
import '../camera_config.dart';
import '../geometry/planar_frame.dart';
import '../rendering/camera_projection.dart';

final class PrincipalPlaneViews {
  static PlanarFrame frame(PrincipalPlane plane) => switch (plane) {
    PrincipalPlane.xy => PlanarFrame.xy(),
    PrincipalPlane.xz => PlanarFrame.xz(),
    PrincipalPlane.yz => PlanarFrame.yz(),
  };

  static List<Vector3> corners(PrincipalPlane plane) => [
    for (final p in [
      Vector2(12, 12),
      Vector2(40, 12),
      Vector2(40, 40),
      Vector2(12, 40),
    ])
      frame(plane).localToWorld(p),
  ];

  static Path path(
    PrincipalPlane plane,
    CameraProjection projection,
    Size size,
  ) {
    final points = projection.clipLoop(
      corners(plane).map(projection.toCameraSpace).toList(),
      screen: size,
    );
    return Path()..addPolygon([
      for (final point in points)
        Offset(
          projection.project(point, screen: size).x,
          projection.project(point, screen: size).y,
        ),
    ], true);
  }

  static ({PrincipalPlane plane, double depth})? pick(
    CameraConfig camera,
    Size size,
    Offset position,
  ) {
    if (size.isEmpty ||
        !position.dx.isFinite ||
        !position.dy.isFinite ||
        !(Offset.zero & size).contains(position)) {
      return null;
    }
    final projection = CameraProjection(camera);
    final pixelRay = Vector3(
      (position.dx - size.width / 2) / camera.focalLength,
      1,
      (size.height / 2 - position.dy) / camera.focalLength,
    );
    final origin =
        camera.position.vector +
        projection.fromCameraDirection(
          camera.isOrthographic
              ? Vector3(
                  pixelRay.x * camera.focusDistance,
                  0,
                  pixelRay.z * camera.focusDistance,
                )
              : Vector3.zero(),
        );
    final direction = projection.fromCameraDirection(
      camera.isOrthographic ? Vector3(0, 1, 0) : pixelRay,
    );
    ({PrincipalPlane plane, double depth})? nearest;
    for (final plane in PrincipalPlane.values) {
      final f = frame(plane);
      final hit = f.intersectRay(rayOrigin: origin, rayDirection: direction);
      if (hit == null) continue;
      final local = f.projectToLocal(hit);
      final depth = projection.toCameraSpace(hit).y;
      if (local.x < 12 ||
          local.x > 40 ||
          local.y < 12 ||
          local.y > 40 ||
          depth < CameraProjection.nearPlane) {
        continue;
      }
      if (nearest == null || depth < nearest.depth) {
        nearest = (plane: plane, depth: depth);
      }
    }
    return nearest;
  }
}
