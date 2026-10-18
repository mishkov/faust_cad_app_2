import 'dart:math' as math;

import '../cad_curves/circular_cad_curve.dart';
import '../cad_curves/linear_cad_curve.dart';
import '../cad_primitivies/face_orientation.dart';
import '../cad_surfaces/cylinder_surface.dart';
import '../geometry/analytic_continuity.dart';
import 'viewport_hit.dart';

final class SelectionMeasurement {
  const SelectionMeasurement(this.kind, this.values);

  final String kind;
  final List<({String label, double value})> values;

  factory SelectionMeasurement.fromHit(ViewportHit hit) {
    final edge = hit.edge;
    if (edge != null) {
      final curve = edge.curve;
      if (curve is CircularCadCurve) {
        return SelectionMeasurement('Arc', [
          (label: 'Length', value: curve.radius * edge.trim!.sweepAngle.abs()),
          (label: 'Radius', value: curve.radius),
        ]);
      }
      return SelectionMeasurement('Edge', [
        if (curve is LinearCadCurve)
          (
            label: 'Length',
            value: (edge.end.vector - edge.begin.vector).length,
          ),
      ]);
    }
    final face = hit.face, surface = face.surface;
    if (surface is CylinderSurface) {
      final axial = [
        for (final edge in face.outerWire.edges)
          (edge.begin.vector - surface.origin).dot(surface.axis),
      ];
      return SelectionMeasurement(
        face.orientation == FaceOrientation.reversed ? 'Hole' : 'Cylinder',
        [
          (label: 'Radius', value: surface.radius),
          (
            label: 'Height',
            value: axial.reduce(math.max) - axial.reduce(math.min),
          ),
        ],
      );
    }
    final edges = face.outerWire.edges;
    final curve = edges.first.curve;
    if (face.innerWires.isEmpty &&
        curve is CircularCadCurve &&
        edges.every(
          (edge) =>
              edge.curve is CircularCadCurve &&
              AnalyticContinuity.sameCircle(
                curve,
                edge.curve as CircularCadCurve,
              ),
        ) &&
        (edges
                        .fold(
                          0.0,
                          (sum, edge) =>
                              sum +
                              edge.trim!.sweepAngle *
                                  curve.frame.normal
                                      .dot(
                                        (edge.curve as CircularCadCurve)
                                            .frame
                                            .normal,
                                      )
                                      .sign,
                        )
                        .abs() -
                    2 * math.pi)
                .abs() <
            1e-9) {
      return SelectionMeasurement('Circle', [
        (label: 'Radius', value: curve.radius),
      ]);
    }
    return const SelectionMeasurement('Face', []);
  }
}
