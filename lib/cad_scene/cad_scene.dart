import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter/material.dart';

export 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
export 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';

class CadScene extends StatefulWidget {
  const new({
    super.key,
    required this.cameraConfig,
    this.cadObjects = const [],
    this.geometry,
    this.renderMode = CadRenderMode.frame,
    this.tessellationSettings,
    this.geometryRevision,
  });

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;
  final List<CadPrimitive>? geometry;

  /// Defaults to the existing wireframe appearance.
  final CadRenderMode renderMode;
  final TessellationSettings? tessellationSettings;

  /// Change to explicitly invalidate derived geometry after model edits.
  final Object? geometryRevision;

  @override
  State<CadScene> createState() => _CadSceneState();
}

class _CadSceneState extends State<CadScene> {
  final _tessellator = SceneTessellator();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CadScenePainter(
        cameraConfig: widget.cameraConfig,
        cadObjects: widget.cadObjects,
        geometry: widget.geometry,
        renderMode: widget.renderMode,
        tessellationSettings: widget.tessellationSettings,
        geometryRevision: widget.geometryRevision,
        tessellator: _tessellator,
      ),
    );
  }
}
