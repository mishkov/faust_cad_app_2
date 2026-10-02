import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
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
    if (size.isEmpty) return;

    for (final cadObject in cadObjects) {
      final primitives = cadObject.build();

      for (final primitive in primitives) {
        _paintPrimitive(canvas, size, primitive);
      }
    }
  }

  void _paintPrimitive(Canvas canvas, Size size, CadPrimitive primitive) {
    switch (primitive) {
      case Face(:final outerWire, :final innerWires):
        // The scene currently renders wireframes. Draw the trimming wires,
        // including holes, using their existing edge geometry.
        _paintPrimitive(canvas, size, outerWire);
        for (final wire in innerWires) {
          _paintPrimitive(canvas, size, wire);
        }
      case Wire(:final edges):
        for (final edge in edges) {
          _paintPrimitive(canvas, size, edge);
        }
      case Edge(begin: Vertex begin, end: Vertex end, curve: LinearCadCurve()):
        final clipped = _clipToViewFrustum(
          _toCameraSpace(begin.vector, cameraConfig),
          _toCameraSpace(end.vector, cameraConfig),
          screen: size,
        );
        if (clipped == null) return;

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

  ({Vector3 begin, Vector3 end})? _clipToViewFrustum(
    Vector3 begin,
    Vector3 end, {
    required Size screen,
  }) {
    final halfWidth = screen.width / (2 * cameraConfig.focalLength);
    final halfHeight = screen.height / (2 * cameraConfig.focalLength);
    final planes = [
      (normal: Vector3(0, 1, 0), offset: -_nearPlane),
      (normal: Vector3(1, halfWidth, 0), offset: 0.0),
      (normal: Vector3(-1, halfWidth, 0), offset: 0.0),
      (normal: Vector3(0, halfHeight, 1), offset: 0.0),
      (normal: Vector3(0, halfHeight, -1), offset: 0.0),
    ];
    var enter = 0.0;
    var exit = 1.0;

    // Clip in camera space before perspective division. Clipping only to the
    // near plane can leave enormous screen coordinates that lose precision
    // when the native renderer converts them to floats.
    for (final plane in planes) {
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

  ({double x, double y}) _project(Vector3 p, {required Size screen}) {
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
