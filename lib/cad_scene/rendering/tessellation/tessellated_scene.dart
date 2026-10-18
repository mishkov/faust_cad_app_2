import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../cad_primitivies/edge.dart';
import '../../geometry/analytic_continuity.dart';

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
  late final Map<Edge, List<Edge>> _circleEdges = _groupCircleEdges();

  List<Edge> selectionEdges(Edge edge) => _circleEdges[edge] ?? [edge];

  Iterable<List<Vector3>> selectionSamples(Edge? edge) sync* {
    if (edge == null) return;
    for (final selected in selectionEdges(edge)) {
      final points = edgeSamples[selected];
      if (points != null) yield points;
    }
  }

  Map<Edge, List<Edge>> _groupCircleEdges() {
    final uses = Map<Object, List<Edge>>.identity();
    for (final edge in edgeSamples.keys) {
      (uses[edge.begin] ??= []).add(edge);
      (uses[edge.end] ??= []).add(edge);
    }
    final groups = <Edge, List<Edge>>{};
    for (final face in faces) {
      for (final wire in [face.source.outerWire, ...face.source.innerWires]) {
        if (!AnalyticContinuity.isFullCircle(wire.edges)) continue;
        for (final edge in wire.edges) {
          for (final use in uses[edge.begin] ?? const <Edge>[]) {
            if (edge.hasSameBoundary(use)) groups[use] = wire.edges;
          }
        }
      }
    }
    return Map.unmodifiable(groups);
  }

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
