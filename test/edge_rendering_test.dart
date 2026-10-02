import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
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

  test('cube renders the boundaries of its solid faces', () {
    final cube = Cube(centerPosition: Vertex(Vector3(0, 10, 0)), size: 2);
    final primitives = cube.build();

    expect(primitives, hasLength(1));
    expect(primitives.single, isA<Solid>());

    final painter = CadScenePainter(cameraConfig: camera, cadObjects: [cube]);
    void paint(Canvas canvas) => painter.paint(canvas, viewport);

    // Each of the twelve geometric edges belongs to two face boundaries.
    expect(paint, paintsExactlyCountTimes(#drawLine, 24));
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
    expect(paint, paints..everything(_hasViewportLineEndpoints(viewport)));
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
            // The visible portion enters the viewport at its right edge.
            expect(clippedPoint.dx, closeTo(200, 1e-9));
            expect(clippedPoint.dy, closeTo(45, 1e-9));
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

  test('clips edges that cross opposite viewport boundaries', () {
    final painter = CadScenePainter(
      cameraConfig: camera,
      cadObjects: [
        _EdgeObject(Vertex(Vector3(-2, 1, 0)), Vertex(Vector3(2, 1, 0))),
        _EdgeObject(Vertex(Vector3(0, 1, 2)), Vertex(Vector3(0, 1, -2))),
      ],
    );
    void paint(Canvas canvas) => painter.paint(canvas, viewport);

    expect(paint, paintsExactlyCountTimes(#drawLine, 2));
    expect(
      paint,
      paints
        ..line(p1: const Offset(0, 100), p2: const Offset(200, 100))
        ..line(p1: const Offset(100, 0), p2: const Offset(100, 200)),
    );
  });

  for (final direction in [
    Vector3(-2, 0, 0),
    Vector3(2, 0, 0),
    Vector3(0, 0, -2),
    Vector3(0, 0, 2),
  ]) {
    test('skips edges outside the viewport in direction $direction', () {
      final painter = CadScenePainter(
        cameraConfig: camera,
        cadObjects: [
          _EdgeObject(
            Vertex(direction + Vector3(0, 1, 0)),
            Vertex(direction + Vector3(0, 1.5, 0)),
          ),
        ],
      );
      expect((Canvas canvas) => painter.paint(canvas, viewport), paintsNothing);
    });
  }

  test('close cursor zoom preserves grid lines crossing the camera plane', () {
    const zoomViewport = Size(700, 600);
    final zoomed = camera
        .copyWith(
          position: Vertex(Vector3(0, -50, 100)),
          pitch: -0.5,
          focalLength: 500,
          focusDistance: 200,
        )
        .zoomTowardCursor(
          cursor: zoomViewport.center(Offset.zero),
          viewport: zoomViewport,
          scaleFactor: 2,
        );
    final painter = CadScenePainter(
      cameraConfig: zoomed,
      cadObjects: [GroundGrid(100, 100)],
    );
    void paint(Canvas canvas) => painter.paint(canvas, zoomViewport);

    // Six crossing edges plus four horizontal edges intersect the viewport.
    expect(paint, paintsExactlyCountTimes(#drawLine, 10));
    expect(paint, paints..line(p1: const Offset(350, 600)));
    expect(paint, paints..everything(_hasViewportLineEndpoints(zoomViewport)));
  });

  test(
    'strong rotated zoom keeps every drawn endpoint inside the viewport',
    () {
      const zoomViewport = Size(700, 600);
      var zoomed = camera.copyWith(
        position: Vertex(Vector3(0, -50, 100)),
        yaw: -0.6,
        pitch: -0.6,
        focalLength: 500,
        focusDistance: 200,
      );
      for (final scale in [2.0, 1.25, 1.25]) {
        zoomed = zoomed.zoomTowardCursor(
          cursor: zoomViewport.center(Offset.zero),
          viewport: zoomViewport,
          scaleFactor: scale,
        );
        final painter = CadScenePainter(
          cameraConfig: zoomed,
          cadObjects: [GroundGrid(100, 100)],
        );
        void paint(Canvas canvas) => painter.paint(canvas, zoomViewport);

        expect(paint, paints..line());
        expect(
          paint,
          paints..everything(_hasViewportLineEndpoints(zoomViewport)),
        );
      }
    },
  );

  test('empty viewport draws nothing', () {
    final painter = CadScenePainter(
      cameraConfig: camera,
      cadObjects: [GroundGrid(100, 100)],
    );
    expect((Canvas canvas) => painter.paint(canvas, Size.zero), paintsNothing);
  });
}

PaintPatternPredicate _hasViewportLineEndpoints(Size viewport) =>
    (method, arguments) {
      if (method != #drawLine) return false;
      final begin = arguments[0] as Offset;
      final end = arguments[1] as Offset;
      for (final point in [begin, end]) {
        expect(point.dx, inInclusiveRange(0, viewport.width));
        expect(point.dy, inInclusiveRange(0, viewport.height));
      }
      return true;
    };

class _EdgeObject extends CadObject {
  _EdgeObject(this.begin, this.end);

  final Vertex begin;
  final Vertex end;

  @override
  List<CadPrimitive> build() => [
    Edge(begin, end, curve: const LinearCadCurve()),
  ];
}
