import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../../document/planar_support.dart';
import '../camera_config.dart';
import '../geometry/geometry_tolerance.dart';
import 'tessellation/tessellated_scene.dart';
import '../selection/principal_plane_views.dart';
import 'camera_projection.dart';

final class SceneGuidesPainter extends CustomPainter {
  const SceneGuidesPainter({
    required this.camera,
    this.showPlanes = false,
    this.showAxes = true,
    this.occluders,
  });
  final CameraConfig camera;
  final bool showPlanes;
  final bool showAxes;
  final TessellatedScene? occluders;

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
    for (var axis = 0; showAxes && axis < 3; axis++) {
      final end = Vector3.zero()..[axis] = length;
      final clipped = projection.clipLine(
        projection.toCameraSpace(Vector3.zero()),
        projection.toCameraSpace(end),
        screen: size,
      );
      if (clipped == null) continue;
      final a = projection.project(clipped.begin, screen: size);
      final b = projection.project(clipped.end, screen: size);
      final begin = Offset(a.x, a.y), endPoint = Offset(b.x, b.y);
      if ((endPoint - begin).distanceSquared < 1e-12) continue;
      final bounds = Rect.fromPoints(begin, endPoint).inflate(2);
      final mask = _axisOcclusion(axis, projection, size, bounds);
      if (mask != null) canvas.saveLayer(bounds, Paint());
      canvas.drawLine(
        begin,
        endPoint,
        Paint()
          ..color = colors[axis]
          ..strokeWidth = 1.2,
      );
      if (mask != null) {
        canvas.drawPath(
          mask,
          Paint()
            ..blendMode = BlendMode.dstOut
            ..isAntiAlias = false,
        );
        canvas.restore();
      }
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

  Path? _axisOcclusion(
    int axis,
    CameraProjection projection,
    Size size,
    Rect bounds,
  ) {
    final scene = occluders;
    if (scene == null || scene.faces.isEmpty) return null;
    // This plane contains the axis. Its positive side is nearer the eye,
    // including for parallel views where eye translation must not affect depth.
    final normal = camera.isOrthographic
        ? projection.fromCameraDirection(Vector3(0, -1, 0))
        : camera.position.vector.clone();
    normal[axis] = 0;
    if (normal.length <= GeometryTolerance.defaults.angular) return null;
    normal.normalize();
    double distance(Vector3 p) =>
        normal.dot(p) - GeometryTolerance.defaults.distance;
    Path? mask;
    for (final face in scene.faces) {
      for (final triangle in face.triangles) {
        final front = <Vector3>[];
        var previous = triangle.points.last;
        var previousDistance = distance(previous);
        for (final point in triangle.points) {
          final d = distance(point);
          if ((d > 0) != (previousDistance > 0)) {
            front.add(
              previous +
                  (point - previous) *
                      (previousDistance / (previousDistance - d)),
            );
          }
          if (d > 0) front.add(point);
          previous = point;
          previousDistance = d;
        }
        if (front.length < 3) continue;
        var points = projection
            .clipLoop(
              front.map(projection.toCameraSpace).toList(),
              screen: size,
            )
            .map((point) {
              final p = projection.project(point, screen: size);
              return Offset(p.x, p.y);
            })
            .toList();
        if (points.length < 3) continue;
        final polygon = Path()..addPolygon(points, true);
        if (!polygon.getBounds().overlaps(bounds)) continue;
        var area = 0.0;
        for (var i = 0; i < points.length; i++) {
          final a = points[i], b = points[(i + 1) % points.length];
          area += a.dx * b.dy - b.dx * a.dy;
        }
        // Same winding makes overlapping surface triangles a union, while
        // actual holes remain clear because the tessellation excludes them.
        if (area < 0) points = points.reversed.toList();
        (mask ??= Path()).addPolygon(points, true);
      }
    }
    return mask;
  }

  static final _center = Vector2(26, 26);

  @override
  bool shouldRepaint(SceneGuidesPainter oldDelegate) =>
      oldDelegate.camera != camera ||
      oldDelegate.showPlanes != showPlanes ||
      oldDelegate.showAxes != showAxes ||
      oldDelegate.occluders != occluders;
}
