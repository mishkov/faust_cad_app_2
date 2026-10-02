import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';

export 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';

class CadScene extends StatefulWidget {
  const new({
    super.key,
    required this.cameraConfig,
    required this.cadObjects,
    this.renderMode = CadRenderMode.frame,
  });

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

  /// Defaults to the existing wireframe appearance.
  final CadRenderMode renderMode;

  @override
  State<CadScene> createState() => _CadSceneState();
}

class _CadSceneState extends State<CadScene> {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CadScenePainter(
        cameraConfig: widget.cameraConfig,
        cadObjects: widget.cadObjects,
        renderMode: widget.renderMode,
      ),
    );
  }
}
