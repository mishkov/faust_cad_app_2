import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter/material.dart';

class CadScenePainter extends CustomPainter {
  CadScenePainter({
    required this.cameraConfig,
    required this.cadObjects,
    this.renderMode = CadRenderMode.frame,
    this.tessellationSettings,
    this.geometryRevision,
    SceneTessellator? tessellator,
  }) : tessellator = tessellator ?? SceneTessellator();

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;
  final CadRenderMode renderMode;
  final TessellationSettings? tessellationSettings;
  final Object? geometryRevision;
  final SceneTessellator tessellator;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scene = tessellator.build(
      cadObjects,
      settings: tessellationSettings,
      geometryRevision: geometryRevision,
    );
    if (renderMode == CadRenderMode.shaded) {
      ShadedSceneRenderer(cameraConfig).paint(canvas, size, scene);
      return;
    }
    final projection = CameraProjection(cameraConfig);
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1;
    for (final edge in scene.edges) {
      for (var i = 0; i < edge.points.length - 1; i++) {
        final clipped = projection.clipLine(
          projection.toCameraSpace(edge.points[i]),
          projection.toCameraSpace(edge.points[i + 1]),
          screen: size,
        );
        if (clipped == null) continue;
        final begin = projection.project(clipped.begin, screen: size);
        final end = projection.project(clipped.end, screen: size);
        canvas.drawLine(Offset(begin.x, begin.y), Offset(end.x, end.y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
