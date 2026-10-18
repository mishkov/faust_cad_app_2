import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_scene/camera_config.dart';
import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/navigation/view_cube.dart';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'cad_screen.dart';

@Preview(
  name: 'CAD model, face selection, and STEP export',
  size: Size(1000, 650),
)
Widget viewportSelectionPreview() => const MaterialApp(home: CadScreen());

@Preview(name: 'Sketch controls at compact size', size: Size(800, 550))
Widget sketchCompactPreview() => const MaterialApp(home: CadScreen());

@Preview(name: 'Camera position cube — dark', size: Size(180, 180))
Widget cameraCubePreview() => _cameraCubePreview(Brightness.dark);

@Preview(name: 'Camera position cube — light', size: Size(180, 180))
Widget cameraCubeLightPreview() => _cameraCubePreview(Brightness.light);

Widget _cameraCubePreview(Brightness brightness) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: Center(
      child: ViewCube(
        camera: CameraConfig(
          position: Vertex(Vector3.zero()),
          yaw: -0.6,
          pitch: -0.5,
          focalLength: 500,
          focusDistance: 200,
        ),
        onSelected: (_) {},
      ),
    ),
  ),
);
