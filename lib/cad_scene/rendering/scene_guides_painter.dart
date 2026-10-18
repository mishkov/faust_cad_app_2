import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../../document/planar_support.dart';
import '../camera_config.dart';
import '../selection/principal_plane_views.dart';
import 'camera_projection.dart';

final class SceneGuidesPainter extends CustomPainter {
  const SceneGuidesPainter({required this.camera, this.showPlanes = false});
  final CameraConfig camera;
  final bool showPlanes;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final projection = CameraProjection(camera);
    // Stay long relative to both camera translation and the visible scale.
    final length = math.max(
      1000000.0,
      (camera.position.vector.length +
              camera.focusDistance *
                  (1 + size.longestSide / camera.focalLength)) *
          100,
    );
    const colors = [Color(0xffc34d52), Color(0xff43a568), Color(0xff4489cc)];
    for (var axis = 0; axis < 3; axis++) {
      final end = Vector3.zero()..[axis] = length;
      final clipped = projection.clipLine(
        projection.toCameraSpace(Vector3.zero()),
        projection.toCameraSpace(end),
        screen: size,
      );
      if (clipped == null) continue;
      final a = projection.project(clipped.begin, screen: size);
      final b = projection.project(clipped.end, screen: size);
      canvas.drawLine(
        Offset(a.x, a.y),
        Offset(b.x, b.y),
        Paint()
          ..color = colors[axis]
          ..strokeWidth = 1.2,
      );
    }
    if (showPlanes) {
      final planes = PrincipalPlane.values.toList()
        ..sort(
          (a, b) => projection
              .toCameraSpace(
                PrincipalPlaneViews.frame(b).localToWorld(
                  // The centers determine a stable back-to-front order.
                  _center,
                ),
              )
              .y
              .compareTo(
                projection
                    .toCameraSpace(
                      PrincipalPlaneViews.frame(a).localToWorld(_center),
                    )
                    .y,
              ),
        );
      for (final plane in planes) {
        final path = PrincipalPlaneViews.path(plane, projection, size);
        canvas.drawPath(path, Paint()..color = const Color(0x44849aaf));
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff849aaf)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.restore();
  }

  static final _center = Vector2(26, 26);

  @override
  bool shouldRepaint(SceneGuidesPainter oldDelegate) =>
      oldDelegate.camera != camera || oldDelegate.showPlanes != showPlanes;
}
