import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'boundary_source.dart';

/// An immutable analytic line or directed circular arc with all source intervals.
class BoundaryPortion {
  /// Creates a line portion with copied endpoints.
  BoundaryPortion.line({
    required Vector2 start,
    required Vector2 end,
    required Iterable<BoundarySource> sources,
  }) : _start = start.clone(),
       _end = end.clone(),
       _center = null,
       radius = null,
       startAngle = null,
       sweepAngle = null,
       sources = List.unmodifiable(sources);

  /// Creates a circular portion, retaining its analytic center, radius and sweep.
  BoundaryPortion.arc({
    required Vector2 center,
    required double radius,
    required double startAngle,
    required double sweepAngle,
    required Iterable<BoundarySource> sources,
  }) : _center = center.clone(),
       radius = radius,
       startAngle = startAngle,
       sweepAngle = sweepAngle,
       _start =
           center +
           Vector2(math.cos(startAngle), math.sin(startAngle)) * radius,
       _end =
           center +
           Vector2(
                 math.cos(startAngle + sweepAngle),
                 math.sin(startAngle + sweepAngle),
               ) *
               radius,
       sources = List.unmodifiable(sources);

  final Vector2 _start;
  final Vector2 _end;
  final Vector2? _center;

  /// Whether this portion is a circular arc.
  bool get isArc => _center != null;

  /// The start point, returned as a defensive copy.
  Vector2 get start => _start.clone();

  /// The end point, returned as a defensive copy.
  Vector2 get end => _end.clone();

  /// The arc center, returned as a defensive copy, or `null` for a line.
  Vector2? get center => _center?.clone();

  /// The arc radius or `null` for a line.
  final double? radius;

  /// The unwrapped start angle in radians or `null` for a line.
  final double? startAngle;

  /// The signed sweep in radians or `null` for a line.
  final double? sweepAngle;

  /// All input intervals contributing to this portion, including duplicates.
  final List<BoundarySource> sources;

  /// Evaluates the analytic boundary at a normalized traversal parameter.
  Vector2 pointAt(double parameter) {
    if (!parameter.isFinite || parameter < 0 || parameter > 1) {
      throw ArgumentError.value(parameter, 'parameter', 'Must be in [0, 1]');
    }
    if (!isArc) return _start + (_end - _start) * parameter;
    final a = startAngle! + sweepAngle! * parameter;
    return _center! + Vector2(math.cos(a), math.sin(a)) * radius!;
  }
}
