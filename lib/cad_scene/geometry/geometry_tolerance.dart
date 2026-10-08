/// Numerical thresholds for model geometry, independent of display scale.
///
/// These thresholds classify numerical agreement; they never snap coordinates,
/// merge vertices, close wires, or bridge separated geometry. Screen-space
/// snapping must use a separate pixel-based policy in future interaction code.
class GeometryTolerance {
  /// Creates finite thresholds with nonnegative [distance] and positive [angular].
  ///
  /// [angular] must be less than one. Throws [ArgumentError] for invalid values.
  factory GeometryTolerance({double distance = 1e-8, double angular = 1e-10}) {
    if (!distance.isFinite || distance < 0) {
      throw ArgumentError.value(
        distance,
        'distance',
        'Must be finite and >= 0',
      );
    }
    if (!angular.isFinite || angular <= 0 || angular >= 1) {
      throw ArgumentError.value(
        angular,
        'angular',
        'Must be finite and in (0, 1)',
      );
    }
    return GeometryTolerance._(distance, angular);
  }

  const GeometryTolerance._(this.distance, this.angular);

  /// The default policy: 1e-8 model units and a 1e-10 angular threshold.
  static const defaults = GeometryTolerance._(1e-8, 1e-10);

  /// The inclusive absolute plane-membership threshold, in model length units.
  ///
  /// No unit such as millimeters is assumed. Choose this for the model's scale
  /// and precision; zero requests exact membership in floating-point arithmetic.
  final double distance;

  /// The dimensionless threshold for unit-vector dot/cross products.
  ///
  /// For parallel directions this bounds the sine of their angle; for
  /// perpendicular directions it bounds the absolute cosine. It also bounds
  /// axis unit-length error. Ray classification is independent of direction
  /// magnitude. This value is neither a length nor a pixel radius.
  final double angular;
}
