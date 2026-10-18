import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../cad_primitivies/edge.dart';

class TessellatedScene {
  TessellatedScene(
    List<TessellatedFace> faces,
    List<({List<Vector3> points, bool boundary})> edges, {
    Map<Edge, List<Vector3>> edgeSamples = const {},
  }) : faces = List.unmodifiable(faces),
       edges = List.unmodifiable(edges),
       edgeSamples = Map.unmodifiable(edgeSamples),
       shadedEdges = List.unmodifiable(
         <({List<Vector3> points, bool boundary})>[...edges]
           ..sort(_compareEdges),
       );

  final List<TessellatedFace> faces;
  final List<({List<Vector3> points, bool boundary})> edges;
  final List<({List<Vector3> points, bool boundary})> shadedEdges;
  final Map<Edge, List<Vector3>> edgeSamples;

  static int _compareEdges(
    ({List<Vector3> points, bool boundary}) a,
    ({List<Vector3> points, bool boundary}) b,
  ) {
    for (var i = 0; i < math.min(a.points.length, b.points.length); i++) {
      for (var axis = 0; axis < 3; axis++) {
        final order = a.points[i][axis].compareTo(b.points[i][axis]);
        if (order != 0) return order;
      }
    }
    return a.points.length.compareTo(b.points.length);
  }
}
