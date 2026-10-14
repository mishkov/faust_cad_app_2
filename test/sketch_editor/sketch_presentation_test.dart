import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/planar_regions/planar_region_engine.dart';
import 'package:faust_cad_app_2/planar_regions/planar_circle.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_presentation.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_view.dart';

import '../support/attachment_fixtures.dart';
import '../support/sketch_fixtures.dart';

void main() {
  test('filled paths and analytic picking preserve holes independently of pixel snapping', () {
    final regions = const PlanarRegionEngine().build([
      PlanarCircle(id: 'outer', center: Vector2.zero(), radius: 10),
      PlanarCircle(id: 'inner', center: Vector2.zero(), radius: 3),
    ]);
    final ring = regions.regions.firstWhere((r) => r.holes.isNotEmpty);
    final path = SketchPresentation.regionPath(ring, (p) => Offset(p.x, p.y));
    expect(path.contains(Offset.zero), isFalse);
    expect(path.contains(const Offset(5, 0)), isTrue);
    final sketch = rectangleSketch(circle: true);
    final solved = const SketchSolver().solve(sketch).geometry!;
    final presentation = SketchPresentation(
      solved: solved,
      regions: const PlanarRegionEngine().build(
        const SketchPlanarAdapter().adaptSolved(solved),
      ),
    );
    final view = const SketchView(scale: 40);
    final hits = presentation.hits(
      view.project(Vector2(1, 1), const Size(400, 400)),
      view,
      const Size(400, 400),
    );
    expect(hits.last.regionId, isNotNull);
  });

  test('inactive sketch fill and strokes are occluded by foreground CAD but visible on a coplanar face', () async {
    final definition = rectangleSketch(width: 8).copyWith(
      points: [
        for (final p in rectangleSketch(width: 8).points.values)
          SketchPoint(id: p.id, x: p.x - 4, y: p.y - 1.5),
      ],
    );
    final frame = PlanarFrame.xy(origin: Vector3(0, 0, 5));
    final camera = CameraConfig(
      position: Vertex(Vector3(0, 0, 20)),
      yaw: 0,
      pitch: -math.pi / 2,
      focalLength: 200,
      focusDistance: 20,
    );
    final painter = SketchScenePainter(
      sketches: [SketchGeometry(definition: definition, frame: frame)],
      camera: camera,
      occluders: SceneTessellator().buildGeometry([
        rectangle(frame),
        rectangle(PlanarFrame.xy(origin: Vector3(4, 0, 8))),
      ]),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    painter.paint(canvas, const Size(400, 400));
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 400);
    final bytes = (await image.toByteData())!;
    List<int> pixel(int x, int y) => [
      for (var i = 0; i < 3; i++) bytes.getUint8((y * 400 + x) * 4 + i),
    ];
    final visible = pixel(173, 200), hidden = pixel(227, 200);
    expect(visible[2], greaterThan(visible[0]));
    expect(hidden, [255, 255, 255]);
    image.dispose();
    picture.dispose();
  });

  test('orthographic projection round trips and cursor zoom stays anchored on every scale', () {
    for (final scale in [0.1, 5.0, 500.0]) {
      final view = SketchView(scale: scale, center: const Offset(15, -10));
      final point = Vector2(-20, 30);
      final cursor = view.project(point, const Size(800, 600));
      expect(
        view.unproject(cursor, const Size(800, 600)).distanceTo(point),
        lessThan(1e-8),
      );
      expect(
        (view
                    .zoom(cursor, const Size(800, 600), 2)
                    .project(point, const Size(800, 600)) -
                cursor)
            .distance,
        lessThan(1e-8),
      );
    }
  });
}
