import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../../../planar_regions/planar_region_engine.dart';
import '../../../sketch/sketch.dart';
import '../../../sketch_editor/presentation/sketch_presentation.dart';
import '../tessellation/trimmed_polygon.dart';
import 'metal_scene_mesh.dart';

/// One immutable upload per solved sketch revision, shared by every camera frame.
final class MetalSketchMesh {
  MetalSketchMesh(SketchGeometry sketch) {
    final frame = sketch.frame, n = frame.normal;
    final regions = const PlanarRegionEngine().build(
      const SketchPlanarAdapter().adaptSolved(sketch.solved),
    );
    final body = <double>[], source = <double>[], lines = <double>[];
    for (final region in regions.regions) {
      final loops = [
        for (final loop in [region.outer, ...region.holes])
          [
            for (final p in SketchPresentation.sampleLoop(loop))
              (uv: p, world: frame.localToWorld(p)),
          ],
      ];
      for (final triangle in TrimmedPolygon.triangulate(
        loops,
        budget: 20000 - body.length ~/ 36,
      )) {
        for (final vertex in triangle) {
          final p = vertex.world;
          body.addAll([...MetalSceneMesh.split(p), n.x, n.y, n.z, 0, -1, 0]);
          source.addAll([p.x, p.y, p.z, n.x, n.y, n.z]);
        }
      }
    }
    void line(Vector2 a, Vector2 b) => MetalSceneMesh.addLine(
      lines,
      frame.localToWorld(a),
      frame.localToWorld(b),
      2,
    );
    for (final segment in sketch.solved.segments.values) {
      line(
        sketch.solved.points[segment.startPointId]!.position,
        sketch.solved.points[segment.endPointId]!.position,
      );
    }
    for (final circle in sketch.solved.circles.values) {
      final c = sketch.solved.points[circle.centerPointId]!.position;
      Vector2 at(int i) =>
          c +
          Vector2(math.cos(i * math.pi / 64), math.sin(i * math.pi / 64)) *
              circle.radius;
      for (var i = 0; i < 128; i++) {
        line(at(i), at(i + 1));
      }
    }
    message = {
      'vertices': Float32List.fromList(body),
      'source': Float64List.fromList(source),
      'indices': Int32List.fromList(List.generate(body.length ~/ 12, (i) => i)),
      'lines': Float32List.fromList(lines),
      'faceCount': 0,
      'plane': Float64List.fromList([
        frame.origin.x,
        frame.origin.y,
        frame.origin.z,
        n.x,
        n.y,
        n.z,
        frame.tolerance.distance,
      ]),
    };
  }
  late final Map<String, Object> message;
}
