import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  final camera = CameraConfig(
    position: Vertex(Vector3.zero()),
    yaw: 0,
    pitch: 0,
    focalLength: 100,
    focusDistance: 10,
  );
  void paint(
    Canvas canvas,
    ShadedSceneRenderer renderer,
    TessellatedScene scene, [
    Size size = const Size(200, 200),
  ]) => renderer.paint(canvas, size, scene);

  test(
    'two adjacent nearer mesh cells jointly hide the entire padded stroke',
    () {
      final mesh = _mesh(_square(5, 2));
      final scene = TessellatedScene(
        [mesh],
        [
          (points: [Vector3(-1, 10, 0), Vector3(1, 10, 0)], boundary: false),
        ],
      );
      final counts = ViewportLayerCounts();
      final renderer = ShadedSceneRenderer(camera, layerCounts: counts);
      expect(
        (Canvas c) => paint(c, renderer, scene),
        paintsExactlyCountTimes(#drawLine, 0),
      );
      expect(counts.hiddenEdges, 1);
      expect(counts.edges, 0);
      expect(counts.meshBatches, 1);
    },
  );
  test('fully covered mesh cells emit no vertices or isolated mesh layers', () {
    final scene = TessellatedScene([_plane(), _mesh(_square(10, 2))], []);
    final counts = ViewportLayerCounts();
    final renderer = ShadedSceneRenderer(camera, layerCounts: counts);
    expect(
      (Canvas c) => paint(c, renderer, scene),
      paintsExactlyCountTimes(#drawVertices, 0),
    );
    expect(counts.hiddenTriangles, 2);
    expect(counts.curvedTriangles, 0);
  });
  test('a hole in the foreground mask retains the original mesh cells', () {
    final scene = TessellatedScene([
      _plane(hole: true),
      _mesh(_square(10, 1)),
    ], []);
    final counts = ViewportLayerCounts();
    final renderer = ShadedSceneRenderer(camera, layerCounts: counts);
    expect(
      (Canvas c) => paint(c, renderer, scene),
      paintsExactlyCountTimes(#drawVertices, 2),
    );
    expect(counts.hiddenTriangles, 0);
  });
  test(
    'partially visible mesh retains vertices after model mutation and resize',
    () {
      final points = _square(10, 2);
      final scene = TessellatedScene([_plane(), _mesh(points)], []);
      final renderer = ShadedSceneRenderer(camera);
      expect(
        (Canvas c) => paint(c, renderer, scene),
        paintsExactlyCountTimes(#drawVertices, 0),
      );
      for (final point in points) {
        point.x += 5;
      }
      for (final size in [const Size(200, 200), const Size(400, 300)]) {
        expect(
          (Canvas c) => paint(c, renderer, scene, size),
          paintsExactlyCountTimes(#drawVertices, 2),
        );
      }
    },
  );
  test('stroke coverage is rebuilt after geometry mutation and resize', () {
    final plane = _plane();
    final scene = TessellatedScene(
      [plane],
      [
        (points: [Vector3(-1, 10, 0), Vector3(1, 10, 0)], boundary: false),
      ],
    );
    final renderer = ShadedSceneRenderer(camera);
    expect(
      (Canvas c) => paint(c, renderer, scene),
      paintsExactlyCountTimes(#drawLine, 0),
    );
    for (final point in plane.loops.single) {
      point.x += 10;
    }
    for (final size in [const Size(200, 200), const Size(400, 300)]) {
      expect(
        (Canvas c) => paint(c, renderer, scene, size),
        paintsExactlyCountTimes(#drawLine, 1),
      );
    }
  });
}

List<Vector3> _square(double depth, double radius) => [
  Vector3(-radius, depth, -radius),
  Vector3(radius, depth, -radius),
  Vector3(radius, depth, radius),
  Vector3(-radius, depth, radius),
];

Wire _wire(List<Vector3> points) {
  final vertices = points.map(Vertex.new).toList();
  return Wire([
    for (var i = 0; i < points.length; i++)
      Edge(
        vertices[i],
        vertices[(i + 1) % points.length],
        curve: const LinearCadCurve(),
      ),
  ]);
}

TessellatedFace _plane({bool hole = false}) {
  final points = _square(5, 3), inner = _square(5, 1);
  final source = Face(
    surface: PlaneSurface(origin: Vector3(0, 5, 0), normal: Vector3(0, -1, 0)),
    outerWire: _wire(points),
    innerWires: hole ? [_wire(inner)] : [],
  );
  return TessellatedFace(source, [points, if (hole) inner], []);
}

// Two synthetic curved tessellation cells sharing a diagonal. Their analytic
// source is deliberately irrelevant: the renderer consumes the sampled mesh.
TessellatedFace _mesh(List<Vector3> points) {
  final source = Face(
    surface: CylinderSurface(frame: PlanarFrame.xy(), radius: 2),
    outerWire: _wire(points),
  );
  final normals = List.generate(3, (_) => Vector3(0, -1, 0));
  return TessellatedFace(
    source,
    [points],
    [
      RenderTriangle([points[0], points[1], points[2]], normals),
      RenderTriangle([points[0], points[2], points[3]], normals),
    ],
  );
}
