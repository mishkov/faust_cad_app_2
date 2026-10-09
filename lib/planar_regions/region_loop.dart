import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'boundary_portion.dart';

/// A closed analytic boundary oriented counterclockwise outside or clockwise inside.
class RegionLoop {
  /// Freezes the ordered portions of a closed boundary.
  RegionLoop(Iterable<BoundaryPortion> portions)
    : portions = List.unmodifiable(portions);

  /// The ordered directed line and arc portions.
  final List<BoundaryPortion> portions;

  /// The signed analytic area, with translation removed for numerical stability.
  double get signedArea {
    final origin = portions.first.start;
    var twiceArea = 0.0;
    for (final edge in portions) {
      final a = edge.start - origin, b = edge.end - origin;
      if (!edge.isArc) {
        twiceArea += a.x * b.y - a.y * b.x;
      } else {
        final c = edge.center! - origin;
        // Integrates x dy - y dx exactly along the analytic arc.
        twiceArea +=
            c.x * (b.y - a.y) -
            c.y * (b.x - a.x) +
            edge.radius! * edge.radius! * edge.sweepAngle!;
      }
    }
    return twiceArea / 2;
  }

  /// Tests boundary proximity without altering connectivity.
  bool onBoundary(Vector2 point, double distance) {
    for (final edge in portions) {
      if (!edge.isArc) {
        final d = edge.end - edge.start;
        final offset = point - edge.start;
        final t = offset.dot(d) / d.length2;
        if (t >= 0 &&
            t <= 1 &&
            (offset.x * d.y - offset.y * d.x).abs() / d.length <= distance) {
          return true;
        }
        if ((point - edge.start).length <= distance ||
            (point - edge.end).length <= distance) {
          return true;
        }
      } else {
        final d = point - edge.center!;
        if ((d.length - edge.radius!).abs() <= distance &&
            _onArc(edge, math.atan2(d.y, d.x), inclusive: true)) {
          return true;
        }
        if ((point - edge.start).length <= distance ||
            (point - edge.end).length <= distance) {
          return true;
        }
      }
    }
    return false;
  }

  /// Tests interior membership by an analytic horizontal ray crossing count.
  ///
  /// Call [onBoundary] first if boundary classification is required.
  bool containsInterior(Vector2 point) {
    var crossings = 0;
    for (final edge in portions) {
      if (!edge.isArc) {
        final a = edge.start, b = edge.end;
        if ((a.y > point.y) != (b.y > point.y) &&
            a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y) > point.x) {
          crossings++;
        }
      } else {
        // Split only the query's angular interval at extrema, not model geometry.
        final begin = edge.startAngle!, finish = begin + edge.sweepAngle!;
        final lo = math.min(begin, finish), hi = math.max(begin, finish);
        final cuts = [lo, hi];
        for (
          var k = ((lo - math.pi / 2) / math.pi).ceil();
          math.pi / 2 + k * math.pi < hi;
          k++
        ) {
          final a = math.pi / 2 + k * math.pi;
          if (a > lo) cuts.add(a);
        }
        cuts.sort();
        final c = edge.center!, r = edge.radius!;
        for (var i = 1; i < cuts.length; i++) {
          final a = cuts[i - 1], b = cuts[i];
          final ya = c.y + r * math.sin(a), yb = c.y + r * math.sin(b);
          if ((ya > point.y) == (yb > point.y)) continue;
          final s = ((point.y - c.y) / r).clamp(-1.0, 1.0);
          final xOffset = r * math.sqrt(math.max(0, 1 - s * s));
          final x = c.x + (math.cos((a + b) / 2) >= 0 ? xOffset : -xOffset);
          if (x > point.x) crossings++;
        }
      }
    }
    return crossings.isOdd;
  }

  static bool _onArc(
    BoundaryPortion e,
    double angle, {
    required bool inclusive,
  }) {
    final sweep = e.sweepAngle!;
    final delta =
        (sweep > 0 ? angle - e.startAngle! : e.startAngle! - angle) %
        (2 * math.pi);
    return inclusive ? delta <= sweep.abs() : delta < sweep.abs();
  }
}
