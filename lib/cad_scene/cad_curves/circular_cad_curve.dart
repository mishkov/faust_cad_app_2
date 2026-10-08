import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

/// An untrimmed analytic circle centered at [frame]'s origin.
///
/// The parameter is an angle in radians: zero lies along the frame's X axis,
/// and increasing angles turn toward Y (counterclockwise viewed from +normal).
/// Angles are periodic with period 2π. This geometry owns no vertices or trim.
class CircularCadCurve extends CadCurve {
  CircularCadCurve({required this.frame, required this.radius}) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(
        radius,
        'radius',
        'Must be finite and positive',
      );
    }
  }

  final PlanarFrame frame;
  final double radius;

  /// The center, returned as a defensive copy.
  Vector3 get center => frame.origin;

  /// Evaluates a finite angle in radians, returning a new world-space point.
  Vector3 evaluate(double angle) {
    _requireAngle(angle);
    return frame.localToWorld(
      Vector2(radius * math.cos(angle), radius * math.sin(angle)),
    );
  }

  /// The derivative with respect to angle (length per radian), not a unit vector.
  Vector3 tangent(double angle) {
    _requireAngle(angle);
    return finiteVector3Result(
      frame.xAxis * (-radius * math.sin(angle)) +
          frame.yAxis * (radius * math.cos(angle)),
    );
  }

  void _requireAngle(double angle) {
    if (!angle.isFinite) {
      throw ArgumentError.value(angle, 'angle', 'Must be finite');
    }
  }
}
