import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_scene/camera_config.dart';
import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/navigation/view_cube.dart';
import '../cad_scene/cad_scene.dart';
import '../cad_scene/cad_objects/ground_grid.dart';
import '../cad_scene/cad_objects/tube.dart';
import '../cad_scene/geometry/planar_frame.dart';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'cad_screen.dart';
import '../cad_scene/selection/selection_badge.dart';
import '../cad_scene/selection/selection_measurement.dart';

@Preview(
  name: 'CAD model, face selection, and STEP export',
  size: Size(1000, 650),
)
Widget viewportSelectionPreview() => const MaterialApp(home: CadScreen());

@Preview(name: 'Sketch controls at compact size', size: Size(800, 550))
Widget sketchCompactPreview() => const MaterialApp(home: CadScreen());

@Preview(name: 'Origin planes and permanent axes', size: Size(700, 550))
Widget sketchPlaneSelectionPreview() => MaterialApp(
  home: Scaffold(
    body: CadScene(
      cameraConfig: CameraConfig(
        position: Vertex(Vector3(110, -160, 120)),
        yaw: 0.6,
        pitch: -0.55,
        focalLength: 500,
        focusDistance: 200,
      ),
      geometry: GroundGrid.withoutAxes().build(),
      renderMode: CadRenderMode.shaded,
      showPrincipalPlanes: true,
    ),
  ),
);

@Preview(
  name: 'Face and edge hover without cylinder seams',
  size: Size(600, 450),
)
Widget faceHoverPreview() => MaterialApp(
  home: Scaffold(
    body: CadScene(
      selectionMode: ViewportSelectionMode.inspect,
      cameraConfig: CameraConfig(
        position: Vertex(Vector3(70, -100, 80)),
        yaw: 0.6,
        pitch: -0.55,
        focalLength: 500,
        focusDistance: 140,
      ),
      cadObjects: [
        Tube(
          frame: PlanarFrame.xy(),
          outerRadius: 20,
          innerRadius: 10,
          height: 10,
        ),
      ],
      renderMode: CadRenderMode.shaded,
    ),
  ),
);

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

@Preview(name: 'Selection measurements — light', size: Size(550, 200))
Widget selectionBadgePreview() => _selectionBadgePreview(Brightness.light);

@Preview(name: 'Selection measurements — dark', size: Size(550, 200))
Widget selectionBadgeDarkPreview() => _selectionBadgePreview(Brightness.dark);

Widget _selectionBadgePreview(Brightness brightness) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          SelectionBadge(
            measurement: SelectionMeasurement('Edge', [
              (label: 'Length', value: 20),
            ]),
          ),
          SelectionBadge(
            measurement: SelectionMeasurement('Hole', [
              (label: 'Radius', value: 5),
              (label: 'Height', value: 20),
            ]),
          ),
        ],
      ),
    ),
  ),
);
