import 'dart:typed_data';

import '../../cad_primitivies/face.dart';
import '../../cad_surfaces/plane_surface.dart';
import '../tessellation/tessellated_scene.dart';

// Camera-independent upload format. Keep CPU packing testable without Impeller.
class GpuSceneMesh {
  GpuSceneMesh(TessellatedScene scene)
    : faces = [for (final face in scene.faces) face.source] {
    final body = <double>[];
    final indices = <int>[];
    final vertices =
        <(double, double, double, double, double, double, int), int>{};
    for (var id = 0; id < scene.faces.length; id++) {
      for (final triangle in scene.faces[id].triangles) {
        for (var i = 0; i < 3; i++) {
          final p = triangle.points[i], n = triangle.normals[i];
          final key = (p.x, p.y, p.z, n.x, n.y, n.z, id);
          final index = vertices.putIfAbsent(key, () {
            final index = body.length ~/ 11;
            body.addAll([
              ..._split(p.x, p.y, p.z),
              n.x,
              n.y,
              n.z,
              0,
              id.toDouble(),
            ]);
            return index;
          });
          indices.add(index);
        }
      }
    }
    bodyVertices = Float32List.fromList(body);
    bodyIndices = Uint32List.fromList(indices);
    final lines = <double>[];
    // Only analytic CAD boundaries and standalone lines, never triangle edges.
    // Deduplicate shared topological uses so MSAA does not darken shared rims.
    final seen = <(double, double, double, double, double, double, bool)>{};
    for (final boundary in [false, true]) {
      for (final edge in scene.shadedEdges.where(
        (e) => e.boundary == boundary,
      )) {
        for (var i = 1; i < edge.points.length; i++) {
          final a = edge.points[i - 1], b = edge.points[i];
          final key = (a.x, a.y, a.z, b.x, b.y, b.z, boundary);
          final reverse = (b.x, b.y, b.z, a.x, a.y, a.z, boundary);
          if (seen.contains(reverse) || !seen.add(key)) continue;
          for (final corner in [
            (0, -1),
            (1, -1),
            (1, 1),
            (0, -1),
            (1, 1),
            (0, 1),
          ]) {
            lines.addAll([
              ..._split(a.x, a.y, a.z),
              ..._split(b.x, b.y, b.z),
              corner.$1.toDouble(),
              corner.$2.toDouble(),
              boundary ? 1 : 0,
            ]);
          }
        }
      }
    }
    edgeVertices = Float32List.fromList(lines);
  }

  final List<Face> faces;
  late final Float32List bodyVertices;
  late final Uint32List bodyIndices;
  late final Float32List edgeVertices;

  void select(Set<Face> selected) {
    for (var i = 0; i < bodyVertices.length; i += 11) {
      final face = faces[bodyVertices[i + 10].toInt()];
      // Match current Canvas selection: only planar surfaces are tinted.
      bodyVertices[i + 9] =
          face.surface is PlaneSurface && selected.contains(face) ? 1 : 0;
    }
  }

  static List<double> _split(double x, double y, double z) {
    final high = Float32List.fromList([x, y, z]);
    return [...high, x - high[0], y - high[1], z - high[2]];
  }

  int get byteLength =>
      bodyVertices.lengthInBytes +
      bodyIndices.lengthInBytes +
      edgeVertices.lengthInBytes;
}
