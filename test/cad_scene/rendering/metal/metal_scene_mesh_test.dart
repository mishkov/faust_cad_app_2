import 'dart:typed_data';

import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_sketch_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../../support/orbit_extrusion_fixture.dart';

void main() {
  test(
    'cube uploads twelve CAD edges without triangle diagonals or duplicates',
    () {
      final scene = SceneTessellator().build([
        Cube(centerPosition: Vertex(Vector3.zero()), size: 20),
      ]);
      final mesh = MetalSceneMesh(scene);
      expect(mesh.bodyIndices.length, 36);
      final decoded = const StandardMessageCodec().decodeMessage(
        const StandardMessageCodec().encodeMessage(mesh.message),
      ) as Map;
      expect(decoded['indices'], isA<Int32List>());
      expect(mesh.edgeVertices.length ~/ 90, 12);
      expect(mesh.faces.length, 6);
      expect(
        mesh.selection(scene.faces.map((f) => f.source).toSet()),
        List.generate(6, (i) => i),
      );
      expect(mesh.bodySource.length, mesh.bodyVertices.length ~/ 2);
    },
  );
  test('high/low positions retain sub-unit detail far from world origin', () {
    final p = Vector3(1000000000.123, -1000000000.456, 1e-9);
    final split = Float32List.fromList(MetalSceneMesh.split(p));
    for (var i = 0; i < 3; i++) {
      expect(split[i] + split[i + 3], closeTo(p[i], 1e-7));
    }
  });
  test('sketch upload contains blue strokes and triangulated region holes', () {
    final mesh = MetalSketchMesh(orbitSketch()).message;
    final lines = mesh['lines']! as Float32List;
    expect(lines.length ~/ 90, 132);
    expect([
      for (var i = 14; i < lines.length; i += 15) lines[i],
    ], everyElement(2));
    expect((mesh['vertices']! as Float32List).length, greaterThan(36));
    expect((mesh['plane']! as Float64List).length, 7);
  });
}
