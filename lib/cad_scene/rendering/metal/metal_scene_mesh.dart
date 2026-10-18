import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../cad_primitivies/face.dart';
import '../../cad_primitivies/edge.dart';
import '../tessellation/tessellated_scene.dart';

/// Camera-independent native upload. Doubles also support precise near clipping.
final class MetalSceneMesh {
  MetalSceneMesh(TessellatedScene scene)
    : _scene = scene,
      faces = [for (final face in scene.faces) face.source] {
    final body = <double>[], source = <double>[];
    final indices = <int>[];
    final vertices =
        <(double, double, double, double, double, double, int), int>{};
    for (var id = 0; id < scene.faces.length; id++) {
      for (final triangle in scene.faces[id].triangles) {
        for (var i = 0; i < 3; i++) {
          final p = triangle.points[i], n = triangle.normals[i];
          indices.add(
            vertices.putIfAbsent((p.x, p.y, p.z, n.x, n.y, n.z, id), () {
              final index = body.length ~/ 12;
              body.addAll([...split(p), n.x, n.y, n.z, 0, id.toDouble(), 0]);
              source.addAll([p.x, p.y, p.z, n.x, n.y, n.z]);
              return index;
            }),
          );
        }
      }
    }
    bodyVertices = Float32List.fromList(body);
    bodySource = Float64List.fromList(source);
    bodyIndices = Uint32List.fromList(indices);
    final lines = <double>[];
    final seen = <(Vector3, Vector3, bool)>{};
    for (final edge in scene.shadedEdges) {
      for (var i = 1; i < edge.points.length; i++) {
        final a = edge.points[i - 1], b = edge.points[i];
        if (seen.contains((b, a, edge.boundary)) ||
            !seen.add((a, b, edge.boundary))) {
          continue;
        }
        addLine(lines, a, b, edge.boundary ? 1 : 0);
      }
    }
    edgeVertices = Float32List.fromList(lines);
  }

  final List<Face> faces;
  final TessellatedScene _scene;
  late final Float32List bodyVertices, edgeVertices;
  late final Float64List bodySource;
  late final Uint32List bodyIndices;

  List<int> selection(Set<Face> selected) => [
    for (var i = 0; i < faces.length; i++)
      if (selected.contains(faces[i])) i,
  ];

  Float32List hoverLines(Face? hoveredFace, {Edge? selectedEdge}) {
    final lines = <double>[];
    for (final face in _scene.faces.where((f) => f.source == hoveredFace)) {
      for (final loop in face.loops) {
        for (var i = 0; i < loop.length; i++) {
          addLine(lines, loop[i], loop[(i + 1) % loop.length], 3);
        }
      }
    }
    for (final points in _scene.selectionSamples(selectedEdge)) {
      for (var i = 1; i < points.length; i++) {
        addLine(lines, points[i - 1], points[i], 3);
      }
    }
    return Float32List.fromList(lines);
  }

  Map<String, Object> get message => {
    'vertices': bodyVertices,
    'source': bodySource,
    'indices': Int32List.view(bodyIndices.buffer),
    'lines': edgeVertices,
    'faceCount': faces.length,
  };

  static List<double> split(Vector3 p) {
    final high = Float32List.fromList([p.x, p.y, p.z]);
    return [...high, p.x - high[0], p.y - high[1], p.z - high[2]];
  }

  static void addLine(List<double> out, Vector3 a, Vector3 b, int kind) {
    for (final c in const [(0, -1), (1, -1), (1, 1), (0, -1), (1, 1), (0, 1)]) {
      out.addAll([
        ...split(a),
        ...split(b),
        c.$1.toDouble(),
        c.$2.toDouble(),
        kind.toDouble(),
      ]);
    }
  }
}
