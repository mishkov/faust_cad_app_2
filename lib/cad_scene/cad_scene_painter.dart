import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:flutter/material.dart';

class CadScenePainter extends CustomPainter {
  const new({
    required this.cameraConfig,
    required this.cadObjects,
    this.renderMode = CadRenderMode.frame,
  });

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

  final CadRenderMode renderMode;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    if (renderMode == CadRenderMode.shaded) {
      ShadedSceneRenderer(cameraConfig).paint(canvas, size, cadObjects);
      return;
    }

    for (final cadObject in cadObjects) {
      final primitives = cadObject.build();

      for (final primitive in primitives) {
        _paintPrimitive(canvas, size, primitive);
      }
    }
  }

  void _paintPrimitive(Canvas canvas, Size size, CadPrimitive primitive) {
    switch (primitive) {
      case Solid(:final shells):
        for (final shell in shells) {
          _paintPrimitive(canvas, size, shell);
        }
      case Shell(:final faces):
        for (final face in faces) {
          _paintPrimitive(canvas, size, face);
        }
      case Face(:final outerWire, :final innerWires):
        // Frame mode draws trimming wires, including holes, using their
        // existing edge geometry.
        _paintPrimitive(canvas, size, outerWire);
        for (final wire in innerWires) {
          _paintPrimitive(canvas, size, wire);
        }
      case Wire(:final edges):
        for (final edge in edges) {
          _paintPrimitive(canvas, size, edge);
        }
      case Edge(begin: Vertex begin, end: Vertex end, curve: LinearCadCurve()):
        final projection = CameraProjection(cameraConfig);
        final clipped = projection.clipLine(
          projection.toCameraSpace(begin.vector),
          projection.toCameraSpace(end.vector),
          screen: size,
        );
        if (clipped == null) return;

        final beginPoint = projection.project(clipped.begin, screen: size);
        final endPoint = projection.project(clipped.end, screen: size);

        canvas.drawLine(
          Offset(beginPoint.x, beginPoint.y),
          Offset(endPoint.x, endPoint.y),
          Paint()
            ..color = Colors.red
            ..strokeWidth = 1,
        );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
