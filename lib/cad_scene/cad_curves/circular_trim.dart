import 'dart:math' as math;

/// A directed, bounded interval on a circle, separate from its geometry.
///
/// [startAngle] is canonicalized into [0, 2π). [sweepAngle] is a signed radian
/// displacement: positive is counterclockwise in the circle's planar frame,
/// negative is clockwise. The sweep must satisfy 0 < |sweep| < 2π; it is never
/// inferred from endpoints. Full circles use multiple edges with shared vertices.
class CircularTrim {
  CircularTrim({required double startAngle, required this.sweepAngle})
    : startAngle = _normalize(startAngle) {
    if (!sweepAngle.isFinite ||
        sweepAngle == 0 ||
        sweepAngle.abs() >= 2 * math.pi) {
      throw ArgumentError.value(
        sweepAngle,
        'sweepAngle',
        'Must satisfy 0 < |sweep| < 2π',
      );
    }
  }

  final double startAngle;
  final double sweepAngle;

  /// The unwrapped terminal angle; it may lie outside [0, 2π).
  double get endAngle => startAngle + sweepAngle;

  /// Converts a normalized traversal parameter in [0, 1] to a circle angle.
  double angleAt(double parameter) {
    if (!parameter.isFinite || parameter < 0 || parameter > 1) {
      throw ArgumentError.value(parameter, 'parameter', 'Must be in [0, 1]');
    }
    return startAngle + sweepAngle * parameter;
  }

  /// The same bounded arc traversed in the opposite direction.
  CircularTrim reversed() =>
      CircularTrim(startAngle: endAngle, sweepAngle: -sweepAngle);

  /// Compares directed intervals, allowing periodic angle roundoff in radians.
  ///
  /// Both start and signed sweep must agree; complementary arcs do not match.
  bool matches(CircularTrim other, {required double angularTolerance}) {
    if (sweepAngle.isNegative != other.sweepAngle.isNegative) return false;
    final difference = (startAngle - other.startAngle).abs();
    final periodicDifference = math.min(difference, 2 * math.pi - difference);
    return periodicDifference <= angularTolerance &&
        (sweepAngle - other.sweepAngle).abs() <= angularTolerance;
  }

  static double _normalize(double angle) {
    if (!angle.isFinite) {
      throw ArgumentError.value(angle, 'startAngle', 'Must be finite');
    }
    return angle % (2 * math.pi);
  }
}
