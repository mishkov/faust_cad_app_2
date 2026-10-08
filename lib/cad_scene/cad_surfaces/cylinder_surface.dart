import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// An infinite analytic cylinder with its axis along [frame]'s normal.
///
/// The frame origin is the axial zero point. Angle zero lies along local X;
/// positive angles turn toward local Y. Angles are in radians and axial values
/// are signed model lengths. Face boundaries define finite patches separately.
class CylinderSurface extends CadSurface {
  /// Creates untrimmed geometry with a finite, positive [radius].
  CylinderSurface({required this.frame, required this.radius}) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError.value(
        radius,
        'radius',
        'Must be finite and positive',
      );
    }
  }

  /// The immutable local coordinate frame.
  final PlanarFrame frame;

  /// The positive radial distance from the axis in model units.
  final double radius;

  /// The axial zero point, returned as a defensive copy.
  Vector3 get origin => frame.origin;

  /// The oriented unit axis, returned as a defensive copy.
  Vector3 get axis => frame.normal;

  /// Evaluates a finite [angle] and signed [axial] distance in world space.
  ///
  /// Neither parameter is trimmed. Throws [ArgumentError] for nonfinite input
  /// and [StateError] if the result exceeds finite numeric range.
  Vector3 evaluate(double angle, double axial) {
    if (!axial.isFinite) {
      throw ArgumentError.value(axial, 'axial', 'Must be finite');
    }
    return finiteVector3Result(origin + normal(angle) * radius + axis * axial);
  }

  /// Returns the outward radial unit normal at a finite [angle].
  ///
  /// The normal is independent of axial position. It follows the right-handed
  /// parameter orientation: the angular derivative crossed with the axial
  /// derivative points outward. Face orientation can negate it for inner walls.
  Vector3 normal(double angle) {
    if (!angle.isFinite) {
      throw ArgumentError.value(angle, 'angle', 'Must be finite');
    }
    return frame.xAxis * math.cos(angle) + frame.yAxis * math.sin(angle);
  }
}
