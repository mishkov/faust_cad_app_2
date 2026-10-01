import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';

class CadScene extends StatefulWidget {
  const new({super.key, required this.cameraConfig, required this.cadObjects});

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

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
      ),
    );
  }
}
