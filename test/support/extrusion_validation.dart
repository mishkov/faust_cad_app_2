import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';

/// Independent divergence-theorem integral over generated analytic surfaces.
/// Uses the B-rep, never region area or the service's distance. Plane flux is
/// constant; cylinder flux integrates radius times radial position exactly over
/// its angular/axial rectangle. Translation reduces cancellation. A negative
/// volume detects inward orientation.
double analyticBoundaryVolume(Solid solid, PlanarFrame placement) {
  var flux = 0.0;
  for (final shell in solid.shells) {
    for (final face in shell.faces) {
      final sign = face.orientation == FaceOrientation.forward ? 1.0 : -1.0;
      final surface = face.surface;
      if (surface is PlaneSurface) {
        var twiceArea = 0.0;
        final origin = face.outerWire.edges.first.begin.vector;
        for (final wire in [face.outerWire, ...face.innerWires]) {
          for (final e in wire.edges) {
            final curve = e.curve;
            if (curve is CircularCadCurve) {
              final trim = e.trim!;
              final c = curve.center - origin;
              final radialChange =
                  curve.evaluate(trim.endAngle) -
                  curve.evaluate(trim.startAngle);
              twiceArea +=
                  surface.normal.dot(c.cross(radialChange)) +
                  curve.radius *
                      curve.radius *
                      trim.sweepAngle *
                      surface.normal.dot(curve.frame.normal);
            } else {
              twiceArea += surface.normal.dot(
                (e.begin.vector - origin).cross(e.end.vector - origin),
              );
            }
          }
        }
        flux +=
            (surface.origin - placement.origin).dot(surface.normal) *
            twiceArea /
            2 *
            sign;
      } else if (surface is CylinderSurface) {
        final arc = face.outerWire.edges.firstWhere(
          (e) => e.curve is CircularCadCurve,
        );
        final trim = arc.trim!;
        final lo = math.min(trim.startAngle, trim.endAngle),
            hi = math.max(trim.startAngle, trim.endAngle);
        final heights = face.outerWire.edges
            .map((e) => (e.begin.vector - surface.origin).dot(surface.axis))
            .toList();
        final height = heights.reduce(math.max) - heights.reduce(math.min);
        final center = surface.origin - placement.origin;
        final integral =
            center.dot(surface.frame.xAxis) * (math.sin(hi) - math.sin(lo)) +
            center.dot(surface.frame.yAxis) * (math.cos(lo) - math.cos(hi)) +
            surface.radius * (hi - lo);
        flux += sign * surface.radius * height * integral;
      } else {
        throw StateError('Unsupported validation surface');
      }
    }
  }
  return flux / 3;
}
