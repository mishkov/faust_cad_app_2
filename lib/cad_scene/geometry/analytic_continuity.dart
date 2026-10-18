import 'dart:math' as math;

import '../cad_curves/circular_cad_curve.dart';
import '../cad_primitivies/edge.dart';
import '../cad_primitivies/face.dart';
import '../cad_surfaces/cylinder_surface.dart';

abstract final class AnalyticContinuity {
  static bool isFullCircle(List<Edge> edges) {
    if (edges.length < 2) return false;
    final circle = edges.first.curve;
    if (circle is! CircularCadCurve) return false;
    var sweep = 0.0;
    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i], curve = edge.curve;
      if (curve is! CircularCadCurve ||
          !sameCircle(circle, curve) ||
          !identical(edge.end, edges[(i + 1) % edges.length].begin)) {
        return false;
      }
      sweep +=
          edge.trim!.sweepAngle *
          circle.frame.normal.dot(curve.frame.normal).sign;
    }
    return (sweep.abs() - 2 * math.pi).abs() < 1e-9;
  }

  static bool sameCircle(CircularCadCurve a, CircularCadCurve b) {
    final distance = math.min(
      a.frame.tolerance.distance,
      b.frame.tolerance.distance,
    );
    final angular = math.min(
      a.frame.tolerance.angular,
      b.frame.tolerance.angular,
    );
    return (a.radius - b.radius).abs() <= distance &&
        (a.center - b.center).length <= distance &&
        a.frame.normal.cross(b.frame.normal).length <= angular;
  }

  static bool sameCylinder(CylinderSurface a, CylinderSurface b) {
    final distance = math.min(
      a.frame.tolerance.distance,
      b.frame.tolerance.distance,
    );
    final angular = math.min(
      a.frame.tolerance.angular,
      b.frame.tolerance.angular,
    );
    final delta = b.origin - a.origin;
    return (a.radius - b.radius).abs() <= distance &&
        a.axis.cross(b.axis).length <= angular &&
        (delta - a.axis * delta.dot(a.axis)).length <= distance;
  }

  static Set<Face> connectedCylinderFaces(Face selected, Iterable<Face> faces) {
    final surface = selected.surface;
    final result = {selected};
    if (surface is! CylinderSurface) return result;
    final remaining =
        faces
            .where(
              (face) =>
                  face.orientation == selected.orientation &&
                  face.surface is CylinderSurface &&
                  sameCylinder(surface, face.surface as CylinderSurface),
            )
            .toSet()
          ..remove(selected);
    final pending = [selected];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      final adjacent = remaining
          .where(
            (face) => current.outerWire.edges.any(
              (edge) => face.outerWire.edges.any(edge.hasSameBoundary),
            ),
          )
          .toList();
      remaining.removeAll(adjacent);
      result.addAll(adjacent);
      pending.addAll(adjacent);
    }
    return result;
  }
}
