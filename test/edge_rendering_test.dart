import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
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

  test('grid clips endpoints on the camera plane and keeps visible edges', () {
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

    expect(paint, paintsExactlyCountTimes(#drawLine, 21));
    expect(
      paint,
      paints..line(p1: const Offset(100, 100), p2: const Offset(100, 100)),
    );
    expect(paint, paints..everything(_hasFiniteLineEndpoints));
  });

  for (final reverse in [false, true]) {
    test(
      'clips a crossing edge with its ${reverse ? 'end' : 'begin'} behind',
      () {
        final behind = Vertex(Vector3(0, -2, 1));
        final visible = Vertex(Vector3(2, 2, 1));
        final painter = CadScenePainter(
          cameraConfig: camera,
          cadObjects: [
            _EdgeObject(reverse ? visible : behind, reverse ? behind : visible),
          ],
        );
        void paint(Canvas canvas) => painter.paint(canvas, viewport);

        expect(paint, paintsExactlyCountTimes(#drawLine, 1));
        expect(
          paint,
          paints..something((method, arguments) {
            if (method != #drawLine) return false;
            final clippedPoint = arguments[reverse ? 1 : 0] as Offset;
            final visiblePoint = arguments[reverse ? 0 : 1] as Offset;
            // The edge meets depth 1e-6 at x = 1 + 0.5e-6, z = 1.
            expect(clippedPoint.dx, closeTo(90000145, 1e-6));
            expect(clippedPoint.dy, closeTo(-89999900, 1e-6));
            expect(visiblePoint, const Offset(190, 55));
            return true;
          }),
        );
        expect(behind.vector, Vector3(0, -2, 1));
        expect(visible.vector, Vector3(2, 2, 1));
      },
    );
  }

  for (final depths in [(-2.0, -1.0), (-1.0, 0.0), (0.0, 0.0)]) {
    test('skips edges entirely behind or on the camera plane: $depths', () {
      final painter = CadScenePainter(
        cameraConfig: camera,
        cadObjects: [
          _EdgeObject(
            Vertex(Vector3(0, depths.$1, 0)),
            Vertex(Vector3(2, depths.$2, 1)),
          ),
        ],
      );
      expect((Canvas canvas) => painter.paint(canvas, viewport), paintsNothing);
    });
  }

  test('close cursor zoom preserves grid lines crossing the camera plane', () {
    final zoomed = camera
        .copyWith(
          position: Vertex(Vector3(0, -50, 100)),
          pitch: -0.5,
          focalLength: 500,
          focusDistance: 200,
        )
        .zoomTowardCursor(
          cursor: viewport.center(Offset.zero),
          viewport: viewport,
          scaleFactor: 5,
        );
    final painter = CadScenePainter(
      cameraConfig: zoomed,
      cadObjects: [GroundGrid(100, 100)],
    );
    void paint(Canvas canvas) => painter.paint(canvas, viewport);

    // Eleven crossing edges plus three edges entirely in front of the camera.
    expect(paint, paintsExactlyCountTimes(#drawLine, 14));
    expect(paint, paints..everything(_hasFiniteLineEndpoints));
  });
}

bool _hasFiniteLineEndpoints(Symbol method, List<dynamic> arguments) {
  if (method != #drawLine) return false;
  final begin = arguments[0] as Offset;
  final end = arguments[1] as Offset;
  return begin.dx.isFinite &&
      begin.dy.isFinite &&
      end.dx.isFinite &&
      end.dy.isFinite;
}

class _EdgeObject extends CadObject {
  _EdgeObject(this.begin, this.end);

  final Vertex begin;
  final Vertex end;

  @override
  List<CadPrimitive> build() => [
    Edge(begin, end, curve: const LinearCadCurve()),
  ];
}
