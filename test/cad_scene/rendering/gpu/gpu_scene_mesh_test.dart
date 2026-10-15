import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/gpu/gpu_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('world positions retain sub-micro-unit offsets after float upload', () {
    final scene = SceneTessellator().build([
      Cube(
        centerPosition: Vertex(Vector3(35.000001, 25.000001, 15.000001)),
        size: 20,
      ),
    ]);
    final mesh = GpuSceneMesh(scene);
    for (var i = 0; i < mesh.bodyVertices.length; i += 11) {
      final p = Vector3(
        mesh.bodyVertices[i] + mesh.bodyVertices[i + 3],
        mesh.bodyVertices[i + 1] + mesh.bodyVertices[i + 4],
        mesh.bodyVertices[i + 2] + mesh.bodyVertices[i + 5],
      );
      final source = scene.faces[mesh.bodyVertices[i + 10].toInt()];
      expect(
        source.triangles
            .expand((t) => t.points)
            .any((v) => v.distanceTo(p) < 1e-10),
        isTrue,
      );
    }
  });
  test(
    'indexed cube keeps face normals and only twelve CAD outline segments',
    () {
      final scene = SceneTessellator().build([
        Cube(centerPosition: Vertex(Vector3.zero()), size: 20),
      ]);
      final mesh = GpuSceneMesh(scene);
      expect(mesh.bodyIndices.length, 36);
      expect(mesh.bodyVertices.length ~/ 11, 24);
      expect(mesh.edgeVertices.length ~/ (15 * 6), 12);
      for (var i = 0; i < mesh.bodyVertices.length; i += 11) {
        expect(mesh.bodyVertices[i + 10], inInclusiveRange(0, 5));
        final n = Vector3(
          mesh.bodyVertices[i + 6],
          mesh.bodyVertices[i + 7],
          mesh.bodyVertices[i + 8],
        );
        expect(n.length, closeTo(1, 1e-6));
      }
      mesh.select({scene.faces.first.source});
      expect(
        [
          for (var i = 9; i < mesh.bodyVertices.length; i += 11)
            mesh.bodyVertices[i],
        ].where((v) => v == 1).length,
        4,
      );
      mesh.select({});
      expect([
        for (var i = 9; i < mesh.bodyVertices.length; i += 11)
          mesh.bodyVertices[i],
      ], everyElement(0));
    },
  );
}
