import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/gpu/gpu_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../test/support/orbit_extrusion_fixture.dart';

Future<List<Map<String, Object>>> compareGpuImages() async {
  const requested = String.fromEnvironment('GPU_REPORT_DIR');
  final output = Directory(
    requested.isEmpty
        ? '${Directory.systemTemp.path}/cad-gpu-images'
        : requested,
  );
  await output.create(recursive: true);
  debugPrint('GPU_IMAGE_OUTPUT ${output.path}');
  final sketch = orbitSketch(), geometry = orbitGeometry(orbitSketch());
  final results = <Map<String, Object>>[];
  for (final name in ['default', 'partial_extrusion', 'tube']) {
    final scene = SceneTessellator().buildGeometry(
      name == 'tube'
          ? Tube(
              frame: PlanarFrame.xy(origin: Vector3(35, 25, 0)),
              outerRadius: 28,
              innerRadius: 16,
              height: 30,
            ).build()
          : name == 'default'
          ? geometry.sublist(0, geometry.length - 1)
          : geometry,
    );
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
    for (var angle = 0; angle < views.length + 5; angle++) {
      final (yaw, pitch) = views[math.min(angle, views.length - 1)];
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
      final size = angle.isEven ? const Size(743, 696) : const Size(640, 480);
      if (angle == 9) camera = camera.pan(const Offset(48, -35));
      if (angle == 10) {
        camera = camera.zoomTowardCursor(
          cursor: const Offset(200, 160),
          viewport: size,
          scaleFactor: 2,
        );
      }
      // A surface crossing the near plane, a camera inside the model, and selection.
      if (angle == 11) {
        camera = camera.copyWith(
          position: Vertex(Vector3(35, 25, 5)),
          focusDistance: 1,
        );
      }
      if (angle == 12) {
        camera = camera.copyWith(
          position: Vertex(Vector3(35, 25, 30) - forward * 1e-6),
          focusDistance: 1,
        );
      }
      final selected = angle == 13
          ? scene.faces.map((f) => f.source).toSet()
          : <Face>{};
      for (final dpr in [1.0, 1.5, 2.0]) {
        final renderer = await GpuSceneRenderer.create();
        final gpuImage = renderer.render(
          camera,
          size,
          dpr,
          scene,
          selected: selected,
        )!;
        await renderer.completed;
        final baseline = await _compose(
          camera,
          scene,
          name == 'partial_extrusion' ? sketch : null,
          size,
          dpr,
          selected,
          null,
        );
        final actual = await _compose(
          camera,
          scene,
          name == 'partial_extrusion' ? sketch : null,
          size,
          dpr,
          selected,
          gpuImage,
        );
        final a = (await baseline.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final b = (await actual.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        var changed = 0, over4 = 0, maxDelta = 0, nonOpaque = 0;
        var squared = 0.0;
        for (var i = 0; i < a.length; i += 4) {
          var delta = 0;
          for (var c = 0; c < 3; c++) {
            final d = (a[i + c] - b[i + c]).abs();
            delta = math.max(delta, d);
            squared += d * d;
          }
          if (delta > 0) changed++;
          if (delta > 4) over4++;
          maxDelta = math.max(maxDelta, delta);
          if (b[i + 3] != 255) nonOpaque++;
        }
        final id = '${name}_${angle}_$dpr';
        results.add({
          'id': id,
          'scene': name,
          'view': angle,
          'dpr': dpr,
          'width': actual.width,
          'height': actual.height,
          'pixels': a.length ~/ 4,
          'changed_pixels': changed,
          'pixels_over_four': over4,
          'maximum_channel_delta': maxDelta,
          'rmse_rgb': math.sqrt(squared / (a.length / 4 * 3)),
          // Diagnostic gate only. Never weaken the existing reference image tests.
          'reference_quality_gate_passed':
              maxDelta <= 4 && changed / (a.length / 4) < 0.005,
        });
        expect(nonOpaque, 0, reason: id);
        await _save(output, '${id}_canvas.png', baseline);
        await _save(output, '${id}_gpu.png', actual);
        baseline.dispose();
        actual.dispose();
        gpuImage.dispose();
        renderer.dispose();
      }
    }
  }
  await File('${output.path}/report.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  return results;
}

Future<void> _save(Directory dir, String name, ui.Image image) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  await File('${dir.path}/$name').writeAsBytes(Uint8List.sublistView(data));
}

Future<ui.Image> _compose(
  CameraConfig camera,
  TessellatedScene scene,
  SketchGeometry? sketch,
  Size size,
  double dpr,
  Set<Face> selected,
  ui.Image? gpuImage,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  canvas.drawColor(Colors.white, BlendMode.src);
  if (gpuImage == null) {
    ShadedSceneRenderer(
      camera,
      devicePixelRatio: dpr,
    ).paint(canvas, size, scene, selectedFaces: selected);
  } else {
    canvas.drawImageRect(
      gpuImage,
      Rect.fromLTWH(
        0,
        0,
        gpuImage.width.toDouble(),
        gpuImage.height.toDouble(),
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
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
    (size.width * dpr).ceil(),
    (size.height * dpr).ceil(),
  );
  picture.dispose();
  return image;
}
