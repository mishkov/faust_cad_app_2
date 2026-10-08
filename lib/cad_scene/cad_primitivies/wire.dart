import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

/// An ordered, non-empty chain of edges connected by shared vertex instances.
///
/// Edges retain their supplied order and orientation. The wire references the
/// original edges and vertices so they can be shared with other topology.
class Wire extends CadPrimitive {
  final List<Edge> edges;

  new(List<Edge> edges) : edges = List<Edge>.unmodifiable(edges) {
    if (this.edges.isEmpty) {
      throw ArgumentError.value(
        edges,
        'edges',
        'A wire needs at least one edge',
      );
    }

    for (var i = 1; i < this.edges.length; i++) {
      if (!identical(this.edges[i - 1].end, this.edges[i].begin)) {
        throw ArgumentError.value(
          edges,
          'edges',
          'Adjacent edges must share the same connecting vertex instance',
        );
      }
    }
  }

  /// Builds a full-circle boundary from exact analytic arcs and shared vertices.
  ///
  /// At least two arcs are required; a single periodic edge/seam is unsupported.
  /// [clockwise] is measured in the circle's frame. No tessellation is generated.
  factory Wire.circular(
    CircularCadCurve circle, {
    int arcCount = 4,
    double startAngle = 0,
    bool clockwise = false,
  }) {
    if (arcCount < 2) {
      throw ArgumentError.value(arcCount, 'arcCount', 'Must be at least two');
    }
    final start = CircularTrim(
      startAngle: startAngle,
      sweepAngle: math.pi,
    ).startAngle;
    final sweep = (clockwise ? -1 : 1) * 2 * math.pi / arcCount;
    final vertices = [
      for (var i = 0; i < arcCount; i++)
        Vertex(circle.evaluate(start + sweep * i)),
    ];
    return Wire([
      for (var i = 0; i < arcCount; i++)
        Edge(
          vertices[i],
          vertices[(i + 1) % arcCount],
          curve: circle,
          trim: CircularTrim(startAngle: start + sweep * i, sweepAngle: sweep),
        ),
    ]);
  }

  /// Reverses edge order and traversal, preserving shared vertices and curves.
  Wire reversed() => Wire([for (final edge in edges.reversed) edge.reversed()]);

  /// Whether the last edge returns to the first edge's starting vertex.
  bool get isClosed => identical(edges.last.end, edges.first.begin);
}
