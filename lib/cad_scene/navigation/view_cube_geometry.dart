import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../camera_config.dart';
import '../rendering/camera_projection.dart';
import 'camera_side.dart';

class ViewCubeGeometry {
  ViewCubeGeometry(CameraConfig camera, this.size)
    : projection = CameraProjection(camera);

  final Size size;
  final CameraProjection projection;
  double get scale => size.shortestSide * 0.19;
  Offset project(Vector3 p) {
    final v = projection.toCameraDirection(p);
    return Offset(
      size.width / 2 + v.x * scale,
      size.height * 0.45 - v.z * scale,
    );
  }

  List<CameraSide> get visibleSides => [
    for (final side in CameraSide.values)
      if (projection.toCameraDirection(side.outward).y < -1e-6) side,
  ];

  List<Offset> corners(CameraSide side) {
    final orientation = side.orientation;
    final right = orientation.fromCameraDirection(Vector3(1, 0, 0));
    final up = orientation.fromCameraDirection(Vector3(0, 0, 1));
    return [
      for (final (x, z) in const [(-1, 1), (1, 1), (1, -1), (-1, -1)])
        project(side.outward + right * x.toDouble() + up * z.toDouble()),
    ];
  }

  Path path(CameraSide side) => Path()..addPolygon(corners(side), true);
}
