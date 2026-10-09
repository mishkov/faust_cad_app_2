import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'planar_input.dart';

/// A full analytic circle with counterclockwise radian parameters from +X.
class PlanarCircle extends PlanarInput {
  /// Copies the finite center and requires a finite positive radius.
  PlanarCircle({
    required String id,
    required Vector2 center,
    required this.radius,
  }) : _center = center.clone(),
       super(id) {
    if (!center.x.isFinite ||
        !center.y.isFinite ||
        !radius.isFinite ||
        radius <= 0) {
      throw ArgumentError('Circle center must be finite and radius positive');
    }
  }
  final Vector2 _center;

  /// The center, returned as a defensive copy.
  Vector2 get center => _center.clone();

  /// The radius in model units.
  final double radius;
}
