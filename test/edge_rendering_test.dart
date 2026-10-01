import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  const viewport = Size(200, 200);
  final camera = CameraConfig(
    position: Vertex(Vector3.zero()),
    yaw: 0,
    pitch: 0,
    focalLength: 90,
    focusDistance: 10,
  );

  test('cube preserves its twelve connected linear edges and rendering', () {
    final cube = Cube(centerPosition: Vertex(Vector3(0, 10, 0)), size: 2);
    final primitives = cube.build();

    expect(primitives, hasLength(12));
    expect(primitives, everyElement(isA<Edge>()));
    final edges = primitives.cast<Edge>();
    expect(
      edges.map((edge) => edge.curve),
      everyElement(isA<LinearCadCurve>()),
    );
    final vertices = edges.expand((edge) => [edge.begin, edge.end]).toSet();
    expect(vertices, hasLength(8));
    for (final vertex in vertices) {
      expect(
        edges.where((edge) => edge.begin == vertex || edge.end == vertex),
        hasLength(3),
      );
    }

    final painter = CadScenePainter(cameraConfig: camera, cadObjects: [cube]);
    void paint(Canvas canvas) => painter.paint(canvas, viewport);

    expect(paint, paintsExactlyCountTimes(#drawLine, 12));
    expect(
      paint,
      paints..line(
        p1: const Offset(90, 110),
        p2: const Offset(110, 110),
        color: Colors.red,
        strokeWidth: 1,
      ),
    );
  });

  test('grid renders linear edges and skips endpoints on the camera plane', () {
    final grid = GroundGrid(20, 40);
    final primitives = grid.build();

    expect(primitives, hasLength(22));
    expect(primitives, everyElement(isA<Edge>()));
    expect(
      primitives.cast<Edge>().map((edge) => edge.curve),
      everyElement(isA<LinearCadCurve>()),
    );

    final painter = CadScenePainter(cameraConfig: camera, cadObjects: [grid]);
    void paint(Canvas canvas) => painter.paint(canvas, viewport);

    expect(paint, paintsExactlyCountTimes(#drawLine, 10));
    expect(
      paint,
      paints
        ..line(p1: const Offset(100, 100), p2: const Offset(550, 100))
        ..line(p1: const Offset(100, 100), p2: const Offset(325, 100)),
    );
  });
}
