import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

/// A non-empty collection of faces connected through shared boundary vertices.
///
/// The shell references the original faces and their topology without copying
/// geometry. Matching coordinates alone do not connect faces. Both outer wires
/// and hole boundaries participate in connectivity, which may be transitive.
/// A shell may be open or closed. [isClosed] checks boundary topology; geometric
/// volume enclosure and surface orientation are the caller's responsibility.
class Shell extends CadPrimitive {
  final List<Face> faces;

  /// Whether the faces form a closed manifold with consistent wire traversal.
  ///
  /// Each boundary edge must occur in exactly two distinct faces, traversed in
  /// opposite directions, each face must visit a boundary vertex only once,
  /// and the faces around each vertex must form one fan.
  /// Edges match by shared endpoint instances and curve instances (all linear
  /// curves describe the same straight segment for a given pair of vertices).
  /// Both outer and inner wires participate. Coincident geometry alone does not
  /// close a shell. This does not check self-intersection or non-zero volume.
  bool get isClosed {
    final distinctFaces = Set<Face>.identity()..addAll(faces);
    if (distinctFaces.length != faces.length) return false;

    final vertexIds = Map<Vertex, int>.identity();
    final curveIds = Map<CadCurve, int>.identity();
    final usesByEdge = <(int, int, int), List<({int face, Edge edge})>>{};
    final fans = Map<Vertex, Map<int, Set<int>>>.identity();
    for (var i = 0; i < faces.length; i++) {
      final faceVertices = Set<Vertex>.identity();
      for (final wire in [faces[i].outerWire, ...faces[i].innerWires]) {
        for (final edge in wire.edges) {
          if (identical(edge.begin, edge.end) ||
              !faceVertices.add(edge.begin)) {
            return false;
          }
          final begin = vertexIds.putIfAbsent(
            edge.begin,
            () => vertexIds.length,
          );
          final end = vertexIds.putIfAbsent(edge.end, () => vertexIds.length);
          final curve = edge.curve is LinearCadCurve
              ? 0
              : curveIds.putIfAbsent(edge.curve, () => curveIds.length + 1);
          final key = begin < end ? (begin, end, curve) : (end, begin, curve);
          (usesByEdge[key] ??= []).add((face: i, edge: edge));
          for (final vertex in [edge.begin, edge.end]) {
            (fans[vertex] ??= {})[i] ??= <int>{};
          }
        }
      }
    }

    for (final uses in usesByEdge.values) {
      if (uses.length != 2) return false;
      final first = uses[0];
      final second = uses[1];
      if (first.face == second.face ||
          !identical(first.edge.begin, second.edge.end) ||
          !identical(first.edge.end, second.edge.begin)) {
        return false;
      }
      for (final vertex in [first.edge.begin, first.edge.end]) {
        fans[vertex]![first.face]!.add(second.face);
        fans[vertex]![second.face]!.add(first.face);
      }
    }

    // Two otherwise closed skins touching at only a vertex are not manifold.
    for (final neighbors in fans.values) {
      final connected = <int>{neighbors.keys.first};
      final pending = <int>[neighbors.keys.first];
      while (pending.isNotEmpty) {
        for (final neighbor in neighbors[pending.removeLast()]!) {
          if (connected.add(neighbor)) pending.add(neighbor);
        }
      }
      if (connected.length != neighbors.length) return false;
    }
    return true;
  }

  new({required List<Face> faces}) : faces = List<Face>.unmodifiable(faces) {
    if (this.faces.isEmpty) {
      throw ArgumentError.value(
        faces,
        'faces',
        'A shell needs at least one face',
      );
    }

    final facesByVertex = Map<Vertex, List<int>>.identity();
    for (var i = 0; i < this.faces.length; i++) {
      final face = this.faces[i];
      for (final wire in [face.outerWire, ...face.innerWires]) {
        for (final edge in wire.edges) {
          (facesByVertex[edge.begin] ??= []).add(i);
          (facesByVertex[edge.end] ??= []).add(i);
        }
      }
    }

    final connected = <int>{0};
    final pending = <int>[0];
    while (pending.isNotEmpty) {
      final face = this.faces[pending.removeLast()];
      for (final wire in [face.outerWire, ...face.innerWires]) {
        for (final edge in wire.edges) {
          for (final vertex in [edge.begin, edge.end]) {
            // Each vertex's neighbors only need to be traversed once.
            for (final neighbor in facesByVertex.remove(vertex) ?? <int>[]) {
              if (connected.add(neighbor)) pending.add(neighbor);
            }
          }
        }
      }
    }

    if (connected.length != this.faces.length) {
      throw ArgumentError.value(
        faces,
        'faces',
        'All faces must be connected through shared boundary vertex instances',
      );
    }
  }
}
