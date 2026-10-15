import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/baseline_shaded_scene_renderer.dart';
import '../../support/orbit_extrusion_fixture.dart';

// Also invoked by rendering_impeller_test.dart to compare the native backend.
Future<List<Map<String, Object>>> compareViewportImages() async {
  final sketch = orbitSketch();
  final geometry = orbitGeometry(sketch);
  final results = <Map<String, Object>>[];
  final views = [
    (-0.95, -0.5),
    (-1.2, -0.05),
    (-0.7, 0.09),
    (0.0, 0.0),
    (0.7, 0.3),
    (-0.95, 0.8),
    (-0.95, 1.2),
    (1.8, -0.7),
    (2.8, 0.5),
  ];
  for (final partial in [false, true]) {
    final scene = SceneTessellator().buildGeometry(
      partial ? geometry : geometry.sublist(0, geometry.length - 1),
    );
    for (var angle = 0; angle < views.length; angle++) {
      final (yaw, pitch) = views[angle];
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
      for (final dpr in [1.0, 2.0]) {
        // Vary viewport dimensions to exercise projection/index invalidation.
        final size = angle.isEven ? const Size(743, 696) : const Size(640, 480);
        final baseline = await _render(
          camera,
          scene,
          partial ? sketch : null,
          size,
          dpr,
          true,
        );
        final optimized = await _render(
          camera,
          scene,
          partial ? sketch : null,
          size,
          dpr,
          false,
        );
        final boundaries = _meshBoundaries(camera, scene, size, dpr);
        var changedPixels = 0, maximumDelta = 0, pixelsOverTwo = 0;
        var maximumBrightening = 0, offBoundaryChanges = 0;
        for (var i = 0; i < baseline.length; i += 4) {
          var changed = false;
          var pixelDelta = 0;
          for (var c = 0; c < 4; c++) {
            final delta = (baseline[i + c] - optimized[i + c]).abs();
            maximumBrightening = math.max(
              maximumBrightening,
              optimized[i + c] - baseline[i + c],
            );
            maximumDelta = math.max(maximumDelta, delta);
            pixelDelta = math.max(pixelDelta, delta);
            changed |= delta != 0;
          }
          if (changed) changedPixels++;
          if (pixelDelta > 2) pixelsOverTwo++;
          if (pixelDelta > 4) {
            final width = (size.width * dpr).round();
            final p = Offset((i ~/ 4 % width) + 0.5, (i ~/ 4 ~/ width) + 0.5);
            if (!boundaries.any((edge) => _nearSegment(p, edge.$1, edge.$2))) {
              offBoundaryChanges++;
            }
          }
        }
        final result = <String, Object>{
          'scene': partial ? 'partial_extrusion' : 'default',
          'angle': angle,
          'dpr': dpr,
          'changed_pixels': changedPixels,
          'maximum_channel_delta': maximumDelta,
          'pixels': baseline.length ~/ 4,
          'pixels_over_two': pixelsOverTwo,
          'maximum_brightening': maximumBrightening,
          'off_boundary_changes_over_four': offBoundaryChanges,
        };
        results.add(result);
      }
    }
  }
  if (const bool.fromEnvironment('VIEWPORT_IMAGE_STATS')) {
    debugPrint('VIEWPORT_IMAGES ${jsonEncode(results)}');
  }
  final output = Platform.environment['VIEWPORT_IMAGE_REPORT'];
  if (output != null) await File(output).writeAsString(jsonEncode(results));
  for (final result in results) {
    // A shared Impeller MSAA submission removes light seams introduced by
    // separately resolving translucent cell edges in the reference layers.
    // Permit only bounded darkening within one physical pixel of a sampled
    // mesh edge. New bright holes and changes to interiors retain tight limits.
    expect(
      result['maximum_channel_delta'],
      lessThanOrEqualTo(32),
      reason: '$result',
    );
    expect(
      result['maximum_brightening'],
      lessThanOrEqualTo(4),
      reason: '$result',
    );
    expect(result['off_boundary_changes_over_four'], 0, reason: '$result');
    expect(
      (result['changed_pixels'] as int) / (result['pixels'] as int),
      lessThan(0.005),
      reason: '$result',
    );
  }
  return results;
}

List<(Offset, Offset)> _meshBoundaries(
  CameraConfig camera,
  TessellatedScene scene,
  Size size,
  double dpr,
) {
  final projection = CameraProjection(camera);
  final result = <(Offset, Offset)>[];
  for (final face in scene.faces) {
    if (face.source.surface is PlaneSurface) continue;
    for (final triangle in face.triangles) {
      final clipped = projection.clipLoop(
        triangle.points.map(projection.toCameraSpace).toList(),
        screen: size,
      );
      final points = [
        for (final p in clipped) projection.project(p, screen: size),
      ];
      for (var i = 0; i < points.length; i++) {
        final p = points[i], q = points[(i + 1) % points.length];
        result.add((
          Offset(p.x * dpr, p.y * dpr),
          Offset(q.x * dpr, q.y * dpr),
        ));
      }
    }
  }
  return result;
}

bool _nearSegment(Offset p, Offset a, Offset b) {
  final delta = b - a;
  final t = delta.distanceSquared == 0
      ? 0.0
      : (((p - a).dx * delta.dx + (p - a).dy * delta.dy) /
                delta.distanceSquared)
            .clamp(0.0, 1.0);
  return (p - a - delta * t).distance <= 1;
}

Future<Uint8List> _render(
  CameraConfig camera,
  TessellatedScene scene,
  SketchGeometry? sketch,
  Size size,
  double dpr,
  bool baseline, {
  Set<Face> selected = const {},
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  canvas.drawColor(Colors.white, BlendMode.src);
  if (baseline) {
    BaselineShadedSceneRenderer(camera)
        .paint(canvas, size, scene, selectedFaces: selected);
  } else {
    ShadedSceneRenderer(camera)
        .paint(canvas, size, scene, selectedFaces: selected);
  }
  if (sketch != null) {
    SketchScenePainter(
      sketches: [sketch],
      camera: camera,
      occluders: scene,
    ).paint(canvas, size);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (size.width * dpr).round(),
    (size.height * dpr).round(),
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Latest main reference matches default and partial extrusion at nine angles and DPR 1/2',
    compareViewportImages,
  );
  test(
    'selection and object order retain reference pixels after resize',
    compareViewportSelectionImages,
  );
}

Future<void> compareViewportSelectionImages() async {
  final geometry = orbitGeometry(orbitSketch());
  final camera = CameraConfig(
    position: Vertex(Vector3(0, -50, 100)),
    yaw: 0,
    pitch: -0.5,
    focalLength: 500,
    focusDistance: 200,
  );
  final tessellator = SceneTessellator();
  final scene = tessellator.buildGeometry(geometry);
  final selected = {
    for (final face in scene.faces)
      if (face.source.surface is PlaneSurface) face.source,
  };
  for (final size in [const Size(743, 696), const Size(640, 480)]) {
    final baseline = await _render(
      camera,
      scene,
      null,
      size,
      2,
      true,
      selected: selected,
    );
    final optimized = await _render(
      camera,
      scene,
      null,
      size,
      2,
      false,
      selected: selected,
    );
    var maximumDelta = 0;
    for (var i = 0; i < baseline.length; i++) {
      maximumDelta = math.max(maximumDelta, (baseline[i] - optimized[i]).abs());
    }
    expect(maximumDelta, lessThanOrEqualTo(2));
    final reversed = tessellator.buildGeometry(
      geometry.reversed.toList(),
      geometryRevision: size,
    );
    expect(
      await _render(camera, reversed, null, size, 2, false, selected: selected),
      orderedEquals(optimized),
    );
  }
}
