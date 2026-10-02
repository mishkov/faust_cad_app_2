import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
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

  void paintPrimitive(Canvas canvas, CadPrimitive primitive) {
    CadScenePainter(
      cameraConfig: camera,
      cadObjects: [_PrimitiveObject(primitive)],
    ).paint(canvas, viewport);
  }

  test('renders standalone wires using their edge geometry', () {
    final wire = _rectangle(2, 10);
    void paint(Canvas canvas) => paintPrimitive(canvas, wire);

    expect(paint, paintsExactlyCountTimes(#drawLine, 4));
    expect(
      paint,
      paints..line(
        p1: const Offset(82, 118),
        p2: const Offset(118, 118),
        color: Colors.red,
        strokeWidth: 1,
      ),
    );
  });

  test('renders the outer boundary and every hole of a face', () {
    final face = Face(
      surface: PlaneSurface(
        origin: Vector3(0, 10, 0),
        normal: Vector3(0, 1, 0),
      ),
      outerWire: _rectangle(3, 10),
      innerWires: [
        _rectangle(0.5, 10, centerX: -1),
        _rectangle(0.5, 10, centerX: 1),
      ],
    );
    void paint(Canvas canvas) => paintPrimitive(canvas, face);

    expect(paint, paintsExactlyCountTimes(#drawLine, 12));
    expect(
      paint,
      paints
        ..line(p1: const Offset(73, 127), p2: const Offset(127, 127))
        ..line()
        ..line()
        ..line()
        ..line(p1: const Offset(86.5, 104.5), p2: const Offset(95.5, 104.5))
        ..line()
        ..line()
        ..line()
        ..line(p1: const Offset(104.5, 104.5), p2: const Offset(113.5, 104.5))
        ..line()
        ..line()
        ..line(),
    );
  });

  test('clips face boundaries through the existing edge frustum clipping', () {
    final face = Face(
      surface: PlaneSurface(origin: Vector3(0, 1, 0), normal: Vector3(0, 1, 0)),
      outerWire: _rectangle(2, 1),
      innerWires: [_rectangle(0.5, 1)],
    );
    void paint(Canvas canvas) => paintPrimitive(canvas, face);

    // The outer boundary surrounds the viewport, so only the hole is visible.
    expect(paint, paintsExactlyCountTimes(#drawLine, 4));
    expect(
      paint,
      paints..line(p1: const Offset(55, 145), p2: const Offset(145, 145)),
    );
  });

  test('renders every shell face, including its hole boundaries', () {
    final outer = _rectangle(3, 10);
    final hole = _rectangle(0.5, 10);
    final surface = PlaneSurface(
      origin: Vector3(0, 10, 0),
      normal: Vector3(0, 1, 0),
    );
    final shell = Shell(
      faces: [
        Face(surface: surface, outerWire: outer, innerWires: [hole]),
        Face(surface: surface, outerWire: hole),
      ],
    );
    void paint(Canvas canvas) => paintPrimitive(canvas, shell);

    expect(paint, paintsExactlyCountTimes(#drawLine, 12));
    expect(
      paint,
      paints
        ..line(p1: const Offset(73, 127), p2: const Offset(127, 127))
        ..line()
        ..line()
        ..line()
        ..line(p1: const Offset(95.5, 104.5), p2: const Offset(104.5, 104.5))
        ..line()
        ..line()
        ..line()
        ..line(p1: const Offset(95.5, 104.5), p2: const Offset(104.5, 104.5))
        ..line()
        ..line()
        ..line(),
    );
  });

  test('skips a face behind the camera', () {
    final face = Face(
      surface: PlaneSurface(
        origin: Vector3(0, -1, 0),
        normal: Vector3(0, 1, 0),
      ),
      outerWire: _rectangle(2, -1),
    );

    expect((Canvas canvas) => paintPrimitive(canvas, face), paintsNothing);
    expect(
      (Canvas canvas) => paintPrimitive(canvas, Shell(faces: [face])),
      paintsNothing,
    );
  });
}

Wire _rectangle(double halfSize, double depth, {double centerX = 0}) {
  final vertices = [
    Vertex(Vector3(centerX - halfSize, depth, -halfSize)),
    Vertex(Vector3(centerX + halfSize, depth, -halfSize)),
    Vertex(Vector3(centerX + halfSize, depth, halfSize)),
    Vertex(Vector3(centerX - halfSize, depth, halfSize)),
  ];
  return Wire([
    for (var i = 0; i < vertices.length; i++)
      Edge(
        vertices[i],
        vertices[(i + 1) % vertices.length],
        curve: const LinearCadCurve(),
      ),
  ]);
}

class _PrimitiveObject extends CadObject {
  _PrimitiveObject(this.primitive);

  final CadPrimitive primitive;

  @override
  List<CadPrimitive> build() => [primitive];
}
