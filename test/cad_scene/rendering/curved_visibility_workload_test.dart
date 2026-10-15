import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/orbit_extrusion_fixture.dart';
import '../../support/baseline_shaded_scene_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real curved workloads resolve partial cells within the frame budget',
    () {
      final sketch = orbitSketch();
      final geometry = orbitGeometry(sketch);
      for (final partial in [false, true]) {
        final scene = SceneTessellator().buildGeometry(
          partial ? geometry : geometry.sublist(0, geometry.length - 1),
        );
        var resolved = 0, savedLayers = 0;
        for (final (yaw, pitch) in [(-0.95, -0.5), (-1.2, -0.05), (0.7, 0.3)]) {
          final forward = Vector3(
            -math.sin(yaw) * math.cos(pitch),
            math.cos(yaw) * math.cos(pitch),
            math.sin(pitch),
          );
          final camera = CameraConfig(
            position: Vertex(Vector3(35, 25, 5) - forward * 220),
            yaw: yaw,
            pitch: pitch,
            focalLength: 500,
            focusDistance: 220,
          );
          final baseline = ViewportLayerCounts(),
              optimized = ViewportLayerCounts();
          final rec = ui.PictureRecorder(), canvas = Canvas(rec);
          BaselineShadedSceneRenderer(
            camera,
            layerCounts: baseline,
          ).paint(canvas, const Size(743, 696), scene);
          ShadedSceneRenderer(
            camera,
            layerCounts: optimized,
          ).paint(canvas, const Size(743, 696), scene);
          rec.endRecording().dispose();
          resolved += optimized.resolvedTriangles;
          savedLayers += baseline.curvedTriangles - optimized.curvedTriangles;
          expect(
            optimized.curvedTriangles,
            lessThanOrEqualTo(baseline.curvedTriangles),
          );
          expect(optimized.maskDraws, lessThanOrEqualTo(baseline.maskDraws));
          expect(optimized.visibilityWork, lessThanOrEqualTo(262144));
        }
        expect(resolved, greaterThan(0));
        expect(savedLayers, greaterThan(0));
      }
    },
  );
}
