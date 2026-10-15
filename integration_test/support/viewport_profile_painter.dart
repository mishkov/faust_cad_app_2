import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../test/support/baseline_shaded_scene_renderer.dart';

class ViewportProfilePainter extends CustomPainter {
  ViewportProfilePainter(
    this.clock,
    this.scene,
    this.sketch,
    this.operation,
    this.baseline,
  ) : super(repaint: clock);
  final ValueNotifier<double> clock;
  final TessellatedScene scene;
  final SketchGeometry? sketch;
  final String operation;
  final bool baseline;
  Size size = Size.zero;
  final layerSamples = <Map<String, int>>[];
  int _paints = 0;
  int get paintCount => _paints;

  @override
  void paint(Canvas canvas, Size size) {
    this.size = size;
    final t = clock.value * math.pi / 3;
    final yaw = operation == 'orbit' ? -0.9 + math.sin(t) * 0.8 : -0.9;
    final pitch = operation == 'orbit' ? -0.5 + math.sin(t * 2) * 0.65 : -0.5;
    final forward = Vector3(
      -math.sin(yaw) * math.cos(pitch),
      math.cos(yaw) * math.cos(pitch),
      math.sin(pitch),
    );
    var camera = CameraConfig(
      position: Vertex(Vector3(35, 25, 5) - forward * 220),
      yaw: yaw,
      pitch: pitch,
      focalLength: 500,
      focusDistance: 220,
    );
    if (operation == 'pan') {
      camera = camera.pan(Offset(60 * math.sin(t), 40 * math.cos(t)));
    }
    if (operation == 'zoom') {
      camera = camera.zoomTowardCursor(
        cursor: size.center(Offset.zero),
        viewport: size,
        scaleFactor: 1 + 0.3 * math.sin(t),
      );
    }
    // Count only one in thirty frames to keep instrumentation off the hot path.
    final layers = _paints++ % 30 == 0 ? ViewportLayerCounts() : null;
    if (baseline) {
      BaselineShadedSceneRenderer(
        camera,
        layerCounts: layers,
      ).paint(canvas, size, scene);
    } else {
      ShadedSceneRenderer(
        camera,
        devicePixelRatio:
            ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
        layerCounts: layers,
      ).paint(canvas, size, scene);
    }
    if (sketch != null) {
      SketchScenePainter(
        sketches: [sketch!],
        camera: camera,
        occluders: scene,
        layerCounts: layers,
      ).paint(canvas, size);
    }
    if (layers != null && layerSamples.length < 512) {
      layerSamples.add(layers.toJson());
    }
  }

  @override
  bool shouldRepaint(ViewportProfilePainter oldDelegate) => true;
}
