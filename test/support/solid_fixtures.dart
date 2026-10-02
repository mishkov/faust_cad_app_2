import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

Shell tetrahedronShell({Vector3? origin, double size = 1, Vertex? corner}) {
  final start = origin ?? Vector3.zero();
  final vertices = [
    corner ?? Vertex(start),
    Vertex(start + Vector3(size, 0, 0)),
    Vertex(start + Vector3(0, size, 0)),
    Vertex(start + Vector3(0, 0, size)),
  ];
  return Shell(
    faces: [
      for (final indices in [
        [0, 2, 1],
        [0, 1, 3],
        [1, 2, 3],
        [2, 0, 3],
      ])
        triangle([for (final index in indices) vertices[index]]),
    ],
  );
}

Face triangle(List<Vertex> vertices) => Face(
  surface: PlaneSurface(
    origin: vertices.first.vector,
    normal: (vertices[1].vector - vertices[0].vector).cross(
      vertices[2].vector - vertices[0].vector,
    ),
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
