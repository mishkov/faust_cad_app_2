import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter/material.dart';

import 'cad_primitivies/face.dart';
import 'cad_primitivies/edge.dart';
import 'rendering/scene_guides_painter.dart';

class CadScenePainter extends CustomPainter {
  CadScenePainter({
    required this.cameraConfig,
    this.cadObjects = const [],
    List<CadPrimitive>? geometry,
    this.renderMode = CadRenderMode.frame,
    this.tessellationSettings,
    this.geometryRevision,
    SceneTessellator? tessellator,
    TessellatedScene? evaluatedScene,
    this.selectedFaces = const {},
    this.selectedEdge,
    this.hoveredFace,
    this.devicePixelRatio = 1,
    this.showGuides = false,
    this.showPrincipalPlanes = false,
  }) : tessellator = tessellator ?? SceneTessellator() {
    // Build render data once before painting. Camera-only paints reuse it.
    scene =
        evaluatedScene ??
        this.tessellator.buildGeometry(
          [...?geometry, for (final object in cadObjects) ...object.build()],
          settings: tessellationSettings,
          geometryRevision: geometryRevision,
        );
  }

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;
  final CadRenderMode renderMode;
  final TessellationSettings? tessellationSettings;
  final Object? geometryRevision;
  final SceneTessellator tessellator;
  late final TessellatedScene scene;
  final Set<Face> selectedFaces;
  final Edge? selectedEdge;
  final Face? hoveredFace;
  final double devicePixelRatio;
  final bool showGuides;
  final bool showPrincipalPlanes;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (showGuides) {
      SceneGuidesPainter(
        camera: cameraConfig,
        showAxes: false,
        showPlanes: showPrincipalPlanes,
      ).paint(canvas, size);
    }
    if (renderMode == CadRenderMode.shaded) {
      ShadedSceneRenderer(
        cameraConfig,
        devicePixelRatio: devicePixelRatio,
      ).paint(
        canvas,
        size,
        scene,
        selectedFaces: selectedFaces,
        selectedEdge: selectedEdge,
        hoveredFace: hoveredFace,
      );
      _paintAxes(canvas, size);
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
    for (final face in scene.faces.where((f) => f.source == hoveredFace)) {
      for (final loop in face.loops) {
        for (var i = 0; i < loop.length; i++) {
          final clipped = projection.clipLine(
            projection.toCameraSpace(loop[i]),
            projection.toCameraSpace(loop[(i + 1) % loop.length]),
            screen: size,
          );
          if (clipped == null) continue;
          final a = projection.project(clipped.begin, screen: size);
          final b = projection.project(clipped.end, screen: size);
          canvas.drawLine(
            Offset(a.x, a.y),
            Offset(b.x, b.y),
            Paint()
              ..color = const Color(0xff00bcd4)
              ..strokeWidth = 2,
          );
        }
      }
    }
    final selectedPoints = scene.edgeSamples[selectedEdge];
    if (selectedPoints != null) {
      for (var i = 1; i < selectedPoints.length; i++) {
        final clipped = projection.clipLine(
          projection.toCameraSpace(selectedPoints[i - 1]),
          projection.toCameraSpace(selectedPoints[i]),
          screen: size,
        );
        if (clipped == null) continue;
        final a = projection.project(clipped.begin, screen: size);
        final b = projection.project(clipped.end, screen: size);
        canvas.drawLine(
          Offset(a.x, a.y),
          Offset(b.x, b.y),
          Paint()
            ..color = const Color(0xff00bcd4)
            ..strokeWidth = 2,
        );
      }
    }
    _paintAxes(canvas, size);
  }

  void _paintAxes(Canvas canvas, Size size) {
    if (showGuides) {
      SceneGuidesPainter(
        camera: cameraConfig,
        occluders: scene,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
