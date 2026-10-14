import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../../planar_regions/planar_region.dart';
import '../../planar_regions/region_loop.dart';
import '../../planar_regions/region_result.dart';
import '../../sketch/sketch.dart';
import '../sketch_hit.dart';
import '../sketch_snap.dart';
import '../sketch_view.dart';

// Shared solved presentation and picking; no CAD primitives are constructed.
final class SketchPresentation {
  const SketchPresentation({required this.solved, required this.regions});
  final SolvedSketch solved;
  final RegionResult? regions;
  static const hitPixels = 8.0;
  static const snapPixels = 10.0;

  List<SketchHit> hits(Offset cursor, SketchView view, Size size) {
    final points = <({SketchEntityId id, double distance})>[];
    for (final point in solved.points.values) {
      final d = (view.project(point.position, size) - cursor).distance;
      if (d <= hitPixels) points.add((id: point.id, distance: d));
    }
    points.sort((a, b) => a.distance.compareTo(b.distance));
    final primitives = <({SketchEntityId id, double distance})>[];
    for (final line in solved.segments.values) {
      final a = view.project(solved.points[line.startPointId]!.position, size);
      final b = view.project(solved.points[line.endPointId]!.position, size);
      final delta = b - a;
      final t = delta.distanceSquared == 0
          ? 0.0
          : (((cursor - a).dx * delta.dx + (cursor - a).dy * delta.dy) /
                    delta.distanceSquared)
                .clamp(0.0, 1.0);
      final d = (cursor - (a + delta * t)).distance;
      if (d <= hitPixels) primitives.add((id: line.id, distance: d));
    }
    for (final circle in solved.circles.values) {
      final center = view.project(
        solved.points[circle.centerPointId]!.position,
        size,
      );
      final d = ((cursor - center).distance - circle.radius * view.scale).abs();
      if (d <= hitPixels) primitives.add((id: circle.id, distance: d));
    }
    primitives.sort((a, b) => a.distance.compareTo(b.distance));
    final local = view.unproject(cursor, size);
    return [
      for (final p in points) SketchHit.entity(SketchHitKind.point, p.id),
      for (final p in primitives)
        SketchHit.entity(SketchHitKind.primitive, p.id),
      for (final r in regions?.regions ?? <PlanarRegion>[])
        if (r.locate(local) == RegionPointLocation.inside)
          SketchHit.region(r.id),
    ];
  }

  SketchSnap snap(
    Offset cursor,
    SketchView view,
    Size size, {
    Vector2? anchor,
  }) {
    SketchPoint? closest;
    var distance = snapPixels;
    for (final point in solved.points.values) {
      final d = (view.project(point.position, size) - cursor).distance;
      if (d < distance) {
        closest = point;
        distance = d;
      }
    }
    if (closest != null) {
      return SketchSnap(
        closest.position,
        'Point ${closest.id} • placement only',
      );
    }
    final local = view.unproject(cursor, size);
    if (anchor != null) {
      if ((local.y - anchor.y).abs() * view.scale < snapPixels) {
        return SketchSnap(
          Vector2(local.x, anchor.y),
          'Horizontal • placement only',
        );
      }
      if ((local.x - anchor.x).abs() * view.scale < snapPixels) {
        return SketchSnap(
          Vector2(anchor.x, local.y),
          'Vertical • placement only',
        );
      }
    }
    return SketchSnap(local, '');
  }

  static Path regionPath(
    PlanarRegion region,
    Offset Function(Vector2) project,
  ) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final loop in [region.outer, ...region.holes]) {
      final points = sampleLoop(loop).map(project).toList();
      if (points.isEmpty) continue;
      path.moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
    }
    return path;
  }

  static List<Vector2> sampleLoop(RegionLoop loop) => [
    for (final edge in loop.portions)
      for (
        var i = 0,
            n = edge.isArc
                ? math.max(4, (edge.sweepAngle!.abs() * 24).ceil())
                : 1;
        i < n;
        i++
      )
        edge.pointAt(i / n),
  ];
}
