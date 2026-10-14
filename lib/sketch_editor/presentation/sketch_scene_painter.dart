import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../../cad_scene/camera_config.dart';
import '../../cad_scene/rendering/camera_projection.dart';
import '../../cad_scene/rendering/tessellation/tessellated_scene.dart';
import '../../sketch/sketch.dart';
import '../../planar_regions/planar_region_engine.dart';
import '../../planar_regions/region_result.dart';
import 'sketch_presentation.dart';

// Inactive sketches share the CAD camera, with foreground topology occlusion.
// The active editor instead shows its infinite plane without solid occlusion.
final class SketchScenePainter extends CustomPainter {
  const SketchScenePainter({
    required this.sketches,
    required this.camera,
    required this.occluders,
  });
  final List<SketchGeometry> sketches;
  final CameraConfig camera;
  final TessellatedScene occluders;
  static final _regionCache = Expando<RegionResult>('solved sketch regions');

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final projection = CameraProjection(camera);
    Offset project(Vector3 p) {
      final v = projection.project(p, screen: size);
      return Offset(v.x, v.y);
    }

    Path polygon(List<Vector3> cameraPoints) {
      var points = projection
          .clipLoop(cameraPoints, screen: size)
          .map(project)
          .toList();
      if (points.length < 3) return Path();
      var area = 0.0;
      for (var i = 0; i < points.length; i++) {
        final a = points[i], b = points[(i + 1) % points.length];
        area += a.dx * b.dy - b.dx * a.dy;
      }
      if (area < 0) points = points.reversed.toList();
      return Path()..addPolygon(points, true);
    }

    for (final sketch in sketches) {
      final frame = sketch.frame;
      final cameraSide = frame.signedDistance(camera.position.vector);
      if (cameraSide.abs() <= frame.tolerance.distance) continue;
      final covered = Path();
      for (final face in occluders.faces) {
        for (final triangle in face.triangles) {
          final front = <Vector3>[];
          var previous = triangle.points.last;
          double side(Vector3 p) =>
              frame.signedDistance(p) * cameraSide.sign -
              frame.tolerance.distance;
          var previousDistance = side(previous);
          for (final p in triangle.points) {
            final distance = side(p);
            if ((distance > 0) != (previousDistance > 0)) {
              front.add(
                previous +
                    (p - previous) *
                        (previousDistance / (previousDistance - distance)),
              );
            }
            if (distance > 0) front.add(p);
            previous = p;
            previousDistance = distance;
          }
          if (front.length >= 3) {
            covered.addPath(
              polygon(front.map(projection.toCameraSpace).toList()),
              Offset.zero,
            );
          }
        }
      }
      canvas.save();
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          covered,
        ),
      );
      final regions = _regionCache[sketch] ??= const PlanarRegionEngine().build(
        const SketchPlanarAdapter().adaptSolved(sketch.solved),
      );
      for (final region in regions.regions) {
        final path = Path()..fillType = PathFillType.evenOdd;
        for (final loop in [region.outer, ...region.holes]) {
          path.addPath(
            polygon(
              SketchPresentation.sampleLoop(loop)
                  .map((p) => projection.toCameraSpace(frame.localToWorld(p)))
                  .toList(),
            ),
            Offset.zero,
          );
        }
        canvas.drawPath(
          path,
          Paint()..color = Colors.blue.withValues(alpha: 0.1),
        );
      }
      final pen = Paint()
        ..strokeWidth = 2
        ..color = Colors.blue;
      void line(Vector2 a, Vector2 b) {
        final clipped = projection.clipLine(
          projection.toCameraSpace(frame.localToWorld(a)),
          projection.toCameraSpace(frame.localToWorld(b)),
          screen: size,
        );
        if (clipped != null) {
          canvas.drawLine(project(clipped.begin), project(clipped.end), pen);
        }
      }

      for (final segment in sketch.solved.segments.values) {
        line(
          sketch.solved.points[segment.startPointId]!.position,
          sketch.solved.points[segment.endPointId]!.position,
        );
      }
      for (final circle in sketch.solved.circles.values) {
        final center = sketch.solved.points[circle.centerPointId]!.position;
        Vector2 at(int i) =>
            center +
            Vector2(math.cos(i * math.pi / 64), math.sin(i * math.pi / 64)) *
                circle.radius;
        for (var i = 0; i < 128; i++) {
          line(at(i), at(i + 1));
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SketchScenePainter oldDelegate) => true;
}
