import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/transform_recording_canvas.dart';

void main() {
  test('shared point transforms are refreshed between paints', () {
    final camera = CameraConfig(
      position: Vertex(Vector3.zero()),
      yaw: 0,
      pitch: 0,
      focalLength: 100,
      focusDistance: 5,
    );
    final points = [
      Vector3(-1, 5, -1),
      Vector3(1, 5, -1),
      Vector3(1, 5, 1),
      Vector3(-1, 5, 1),
    ];
    final vertices = points.map(Vertex.new).toList();
    final face = Face(
      surface: PlaneSurface(
        origin: Vector3(0, 5, 0),
        normal: Vector3(0, -1, 0),
      ),
      outerWire: Wire([
        for (var i = 0; i < vertices.length; i++)
          Edge(
            vertices[i],
            vertices[(i + 1) % vertices.length],
            curve: const LinearCadCurve(),
          ),
      ]),
    );
    final scene = TessellatedScene([
      TessellatedFace(face, [points], []),
    ], []);
    final renderer = ShadedSceneRenderer(camera);
    void expectBounds(Rect expected) {
      final canvas = TransformRecordingCanvas();
      renderer.paint(canvas, const Size(200, 200), scene);
      final paths = canvas.invocations.where(
        (call) => call.invocation.memberName == #drawPath,
      );
      expect(paths, hasLength(1));
      expect(
        (paths.single.invocation.positionalArguments[0] as Path).getBounds(),
        expected,
      );
    }

    expectBounds(const Rect.fromLTRB(80, 80, 120, 120));
    for (final point in points) {
      point.x += 1;
    }
    expectBounds(const Rect.fromLTRB(100, 80, 140, 120));
    camera.position.vector.x += 1;
    expectBounds(const Rect.fromLTRB(80, 80, 120, 120));
  });
}
