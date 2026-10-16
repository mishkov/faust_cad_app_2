import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../cad_scene/cad_primitivies/cad_primitive.dart';
import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/cad_render_mode.dart';
import '../cad_scene/cad_scene_painter.dart';
import '../cad_scene/camera_config.dart';
import '../cad_scene/rendering/tessellation/scene_tessellator.dart';
import '../cad_scene/rendering/tessellation/tessellated_scene.dart';
import '../document/document_controller.dart';

/// Renders document bodies without reading or changing the interactive camera.
final class AutomationRenderer {
  AutomationRenderer(this.document);
  final DocumentController document;

  Future<Map<String, Object?>> render(Map<String, Object?> args) async {
    final revision = document.evaluation.revision;
    final scene = await compute(
      _tessellate,
      document.evaluation.materializeGeometry().geometry,
    );
    final points = [for (final edge in scene.edges) ...edge.points];
    final low = Vector3.zero(), high = Vector3.zero();
    if (points.isNotEmpty) {
      low.setFrom(points.first);
      high.setFrom(points.first);
      for (final p in points) {
        low.setValues(
          math.min(low.x, p.x),
          math.min(low.y, p.y),
          math.min(low.z, p.z),
        );
        high.setValues(
          math.max(high.x, p.x),
          math.max(high.y, p.y),
          math.max(high.z, p.z),
        );
      }
    }
    final center = (low + high) / 2;
    final target = args['target'] as List?;
    if (target != null) {
      center.setValues(
        (target[0] as num).toDouble(),
        (target[1] as num).toDouble(),
        (target[2] as num).toDouble(),
      );
    }
    final width = args['width'] as int? ?? 800;
    final height = args['height'] as int? ?? 600;
    final distance =
        (args['distance'] as num?)?.toDouble() ??
        math.max(30, (high - low).length * 1.8);
    final yaw = ((args['yaw'] as num?)?.toDouble() ?? -25) * math.pi / 180;
    final pitch = ((args['pitch'] as num?)?.toDouble() ?? -55) * math.pi / 180;
    final forward = Vector3(
      -math.sin(yaw) * math.cos(pitch),
      math.cos(yaw) * math.cos(pitch),
      math.sin(pitch),
    );
    final camera = CameraConfig(
      position: Vertex(center - forward * distance),
      yaw: yaw,
      pitch: pitch,
      focalLength: math.min(width, height).toDouble(),
      focusDistance: distance,
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xfffafafa), ui.BlendMode.src);
    CadScenePainter(
      cameraConfig: camera,
      evaluatedScene: scene,
      renderMode: CadRenderMode.shaded,
    ).paint(canvas, ui.Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed');
      return {
        'content': [
          {
            'type': 'text',
            'text': jsonEncode({
              'revision': revision,
              'target': [center.x, center.y, center.z],
              'distance': distance,
              'yaw': yaw * 180 / math.pi,
              'pitch': pitch * 180 / math.pi,
            }),
          },
          {
            'type': 'image',
            'mimeType': 'image/png',
            'data': base64Encode(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            ),
          },
        ],
      };
    } finally {
      image.dispose();
      picture.dispose();
    }
  }
}

TessellatedScene _tessellate(List<CadPrimitive> geometry) =>
    SceneTessellator().buildGeometry(geometry);
