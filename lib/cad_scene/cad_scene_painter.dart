import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class CadScenePainter extends CustomPainter {
  const new({required this.cameraConfig, required this.cadObjects});

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

  // Keep perspective division away from the camera plane at depth zero.
  static const double _nearPlane = 1e-6;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cadObject in cadObjects) {
      final primitives = cadObject.build();

      for (final primitive in primitives) {
        switch (primitive) {
          case Edge(
            begin: Vertex begin,
            end: Vertex end,
            curve: LinearCadCurve(),
          ):
            final clipped = _clipToNearPlane(
              _toCameraSpace(begin.vector, cameraConfig),
              _toCameraSpace(end.vector, cameraConfig),
            );
            if (clipped == null) {
              break;
            }

            final beginPoint = _project(clipped.begin, screen: size);
            final endPoint = _project(clipped.end, screen: size);

            canvas.drawLine(
              Offset(beginPoint.x, beginPoint.y),
              Offset(endPoint.x, endPoint.y),
              Paint()
                ..color = Colors.red
                ..strokeWidth = 1,
            );
        }
      }
    }
  }

  ({Vector3 begin, Vector3 end})? _clipToNearPlane(Vector3 begin, Vector3 end) {
    final beginVisible = begin.y >= _nearPlane;
    final endVisible = end.y >= _nearPlane;
    if (!beginVisible && !endVisible) return null;

    if (beginVisible != endVisible) {
      // Preserve the visible part of an edge whose other endpoint is behind
      // the near plane, instead of discarding the whole edge.
      final t = (_nearPlane - begin.y) / (end.y - begin.y);
      final intersection = begin + (end - begin) * t;
      intersection.y = _nearPlane;
      if (!beginVisible) {
        begin = intersection;
      } else {
        end = intersection;
      }
    }

    return (begin: begin, end: end);
  }

  ({double x, double y}) _project(Vector3 p, {required Size screen}) {
    return (
      x: screen.width / 2 + p.x / p.y * cameraConfig.focalLength,
      y: screen.height / 2 - p.z / p.y * cameraConfig.focalLength,
    );
  }

  Vector3 _toCameraSpace(Vector3 point, CameraConfig camera) {
    var p = point - camera.position.vector;

    // Inverse camera yaw: rotate around Z
    final cy = math.cos(-camera.yaw);
    final sy = math.sin(-camera.yaw);

    final x1 = p.x * cy - p.y * sy;
    final y1 = p.x * sy + p.y * cy;
    final z1 = p.z;

    // Inverse camera pitch: rotate around X
    final cp = math.cos(-camera.pitch);
    final sp = math.sin(-camera.pitch);

    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;

    return Vector3(x1, y2, z2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}
