import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/point3d.dart';
import 'package:flutter/material.dart';

class CameraConfig with Equatable {
  final Point3d position;
  final double yaw;
  final double pitch;
  final double focalLength;

  /// Camera-space depth of the point used for cursor zoom.
  final double focusDistance;

  new({
    required this.position,
    required this.yaw,
    required this.pitch,
    required this.focalLength,
    required this.focusDistance,
  }) : assert(focalLength.isFinite && focalLength > 0),
       assert(focusDistance.isFinite && focusDistance > 0);

  @override
  List<Object?> get props => [position, yaw, pitch, focalLength, focusDistance];

  CameraConfig copyWith({
    Point3d? position,
    double? yaw,
    double? pitch,
    double? focalLength,
    double? focusDistance,
  }) {
    return CameraConfig(
      position: position ?? this.position,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      focalLength: focalLength ?? this.focalLength,
      focusDistance: focusDistance ?? this.focusDistance,
    );
  }

  CameraConfig zoomTowardCursor({
    required Offset cursor,
    required Size viewport,
    required double scaleFactor,
  }) {
    if (!scaleFactor.isFinite ||
        scaleFactor <= 0 ||
        scaleFactor == 1 ||
        viewport.isEmpty) {
      return this;
    }

    // Reverse the painter's perspective projection to get the cursor ray.
    final rayX = (cursor.dx - viewport.width / 2) / focalLength;
    final rayZ = (viewport.height / 2 - cursor.dy) / focalLength;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final pitchedY = cp - rayZ * sp;
    final directionZ = sp + rayZ * cp;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final directionX = rayX * cy - pitchedY * sy;
    final directionY = rayX * sy + pitchedY * cy;

    // A screen position defines a ray, so use the camera's focus depth to
    // choose a point on that ray, regardless of which way it points.
    final distance = focusDistance;
    // Pinching out increases scale and moves the camera along the cursor ray.
    final factor = 1 / scaleFactor.clamp(0.2, 5.0);
    final step = distance * (1 - factor);
    return copyWith(
      position: Point3d(
        position.x + directionX * step,
        position.y + directionY * step,
        position.z + directionZ * step,
      ),
      focusDistance: distance * factor,
    );
  }
}
