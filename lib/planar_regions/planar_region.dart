import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'region_loop.dart';

/// The result of a point-in-material query, distinguishing the boundary.
enum RegionPointLocation { outside, inside, boundary }

/// A bounded selectable material cell with one outer loop and zero or more holes.
class PlanarRegion {
  /// Creates an immutable region with an arrangement-local identity.
  PlanarRegion({
    required this.id,
    required this.outer,
    Iterable<RegionLoop> holes = const [],
  }) : holes = List.unmodifiable(holes);

  /// The deterministic identity within this arrangement, not a persistent reference.
  final String id;

  /// The counterclockwise external boundary.
  final RegionLoop outer;

  /// The clockwise inner boundaries.
  final List<RegionLoop> holes;

  /// The analytic material area, excluding holes.
  double get area =>
      outer.signedArea + holes.fold(0.0, (a, h) => a + h.signedArea);

  /// Classifies a finite point using a separate, nonnegative proximity distance.
  ///
  /// The query distance never snaps geometry or changes region topology.
  RegionPointLocation locate(Vector2 point, {double boundaryDistance = 0}) {
    if (!point.x.isFinite ||
        !point.y.isFinite ||
        !boundaryDistance.isFinite ||
        boundaryDistance < 0) {
      throw ArgumentError(
        'Point and boundary distance must be finite; distance >= 0',
      );
    }
    if ([outer, ...holes].any((l) => l.onBoundary(point, boundaryDistance))) {
      return RegionPointLocation.boundary;
    }
    return outer.containsInterior(point) &&
            !holes.any((h) => h.containsInterior(point))
        ? RegionPointLocation.inside
        : RegionPointLocation.outside;
  }
}
