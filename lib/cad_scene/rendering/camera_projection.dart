import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// Shared camera transforms and clipping for both rendering modes.
class CameraProjection {
  const CameraProjection(this.cameraConfig);

  final CameraConfig cameraConfig;
  static const double _nearPlane = 1e-6;

  List<({Vector3 normal, double offset})> _planes(Size screen) {
    final halfWidth = screen.width / (2 * cameraConfig.focalLength);
    final halfHeight = screen.height / (2 * cameraConfig.focalLength);
    return [
      (normal: Vector3(0, 1, 0), offset: -_nearPlane),
      (normal: Vector3(1, halfWidth, 0), offset: 0.0),
      (normal: Vector3(-1, halfWidth, 0), offset: 0.0),
      (normal: Vector3(0, halfHeight, 1), offset: 0.0),
      (normal: Vector3(0, halfHeight, -1), offset: 0.0),
    ];
  }

  /// Clips a closed trimming loop before performing perspective division.
  List<Vector3> clipLoop(List<Vector3> points, {required Size screen}) {
    for (final plane in _planes(screen)) {
      if (points.isEmpty) break;
      final output = <Vector3>[];
      var previous = points.last;
      var previousDistance = plane.normal.dot(previous) + plane.offset;
      for (final point in points) {
        final distance = plane.normal.dot(point) + plane.offset;
        if ((distance >= 0) != (previousDistance >= 0)) {
          output.add(
            previous +
                (point - previous) *
                    (previousDistance / (previousDistance - distance)),
          );
        }
        if (distance >= 0) output.add(point);
        previous = point;
        previousDistance = distance;
      }
      points = output;
    }
    return points;
  }

  ({Vector3 begin, Vector3 end})? clipLine(
    Vector3 begin,
    Vector3 end, {
    required Size screen,
  }) {
    var enter = 0.0;
    var exit = 1.0;

    // Clip in camera space before perspective division. Clipping only to the
    // near plane can leave enormous screen coordinates that lose precision
    // when the native renderer converts them to floats.
    for (final plane in _planes(screen)) {
      final beginDistance = plane.normal.dot(begin) + plane.offset;
      final endDistance = plane.normal.dot(end) + plane.offset;
      if (beginDistance < 0 && endDistance < 0) return null;
      if (beginDistance < 0 || endDistance < 0) {
        final t = beginDistance / (beginDistance - endDistance);
        if (beginDistance < 0) {
          enter = math.max(enter, t);
        } else {
          exit = math.min(exit, t);
        }
        if (enter > exit) return null;
      }
    }

    final direction = end - begin;
    return (begin: begin + direction * enter, end: begin + direction * exit);
  }

  ({double x, double y}) project(Vector3 p, {required Size screen}) {
    final depth = math.max(p.y, _nearPlane);
    // Clamp tiny rounding errors at the clipping planes to the viewport.
    return (
      x: (screen.width / 2 + p.x / depth * cameraConfig.focalLength)
          .clamp(0.0, screen.width)
          .toDouble(),
      y: (screen.height / 2 - p.z / depth * cameraConfig.focalLength)
          .clamp(0.0, screen.height)
          .toDouble(),
    );
  }

  Vector3 toCameraSpace(Vector3 point) {
    return toCameraDirection(point - cameraConfig.position.vector);
  }

  /// Rotate a direction without introducing camera translation.
  Vector3 toCameraDirection(Vector3 p) {
    // Inverse camera yaw: rotate around Z
    final cy = math.cos(-cameraConfig.yaw);
    final sy = math.sin(-cameraConfig.yaw);

    final x1 = p.x * cy - p.y * sy;
    final y1 = p.x * sy + p.y * cy;
    final z1 = p.z;

    // Inverse camera pitch: rotate around X
    final cp = math.cos(-cameraConfig.pitch);
    final sp = math.sin(-cameraConfig.pitch);

    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;

    return Vector3(x1, y2, z2);
  }
}
