import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';

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

  /// Whether the last edge returns to the first edge's starting vertex.
  bool get isClosed => identical(edges.last.end, edges.first.begin);
}
