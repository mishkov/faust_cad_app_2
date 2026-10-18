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

  // Cube regions closer than a line, or a label at a constant camera depth.
  Path occlusionPath(Vector3 begin, [Vector3? end]) {
    final start = project(begin);
    final delta = end == null ? Offset.zero : project(end) - start;
    final depth = projection.toCameraDirection(begin).y;
    final gradient = delta.distanceSquared < 1e-12 || end == null
        ? 0.0
        : (projection.toCameraDirection(end).y - depth) / delta.distanceSquared;
    final mask = Path();
    for (final side in visibleSides) {
      final normal = projection.toCameraDirection(side.outward);
      double difference(Offset point) {
        final x = (point.dx - size.width / 2) / scale;
        final z = (size.height * 0.45 - point.dy) / scale;
        final faceDepth = (1 - normal.x * x - normal.z * z) / normal.y;
        final along = point - start;
        final axisDepth =
            depth + gradient * (along.dx * delta.dx + along.dy * delta.dy);
        return axisDepth - faceDepth - 1e-8;
      }

      final polygon = corners(side);
      final clipped = <Offset>[];
      var previous = polygon.last;
      var previousDistance = difference(previous);
      for (final point in polygon) {
        final distance = difference(point);
        if ((distance > 0) != (previousDistance > 0)) {
          clipped.add(
            previous +
                (point - previous) *
                    (previousDistance / (previousDistance - distance)),
          );
        }
        if (distance > 0) clipped.add(point);
        previous = point;
        previousDistance = distance;
      }
      if (clipped.length >= 3) mask.addPolygon(clipped, true);
    }
    return mask;
  }
}
