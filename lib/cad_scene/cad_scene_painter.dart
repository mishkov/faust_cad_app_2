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
            final beginPoint = _project(
              begin.vector,
              cameraConfig,
              screen: size,
            );
            final endPoint = _project(end.vector, cameraConfig, screen: size);

            if (beginPoint == null || endPoint == null) {
              break;
            }

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

  ({double x, double y})? _project(
    Vector3 point,
    CameraConfig camera, {
    required Size screen,
  }) {
    final p = _toCameraSpace(point, camera);

    final befindCamera = p.y <= 0;
    if (befindCamera) return null;

    return (
      x: screen.width / 2 + p.x / p.y * camera.focalLength,
      y: screen.height / 2 - p.z / p.y * camera.focalLength,
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
