import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

/// A non-empty collection of faces connected through shared boundary vertices.
///
/// The shell references the original faces and their topology without copying
/// geometry. Matching coordinates alone do not connect faces. Both outer wires
/// and hole boundaries participate in connectivity, which may be transitive.
/// A shell may be open or closed; volume enclosure, manifoldness, and consistent
/// face orientation are the caller's responsibility.
class Shell extends CadPrimitive {
  final List<Face> faces;

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
