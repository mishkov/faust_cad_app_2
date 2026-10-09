import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

PlanarFrame tiltedFrame(double angle, {double height = 0}) => PlanarFrame(
  origin: Vector3(0, 0, height),
  xAxis: Vector3(math.cos(angle), 0, -math.sin(angle)),
  yAxis: Vector3(0, 1, 0),
);

Face rectangle(PlanarFrame frame, {bool hole = false}) {
  Wire loop(double size) {
    final vertices = [
      for (final p in [
        Vector2(-size, -size),
        Vector2(size, -size),
        Vector2(size, size),
        Vector2(-size, size),
      ])
        Vertex(frame.localToWorld(p)),
    ];
    return Wire([
      for (var i = 0; i < 4; i++)
        Edge(vertices[i], vertices[(i + 1) % 4], curve: const LinearCadCurve()),
    ]);
  }

  return Face(
    surface: PlaneSurface(origin: frame.origin, normal: frame.normal),
    outerWire: loop(4),
    innerWires: [if (hole) loop(1).reversed()],
  );
}
