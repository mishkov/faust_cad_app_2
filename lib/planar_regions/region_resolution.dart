import 'planar_region.dart';
import 'region_reference.dart';

/// An explicit resolution status and all candidates, never a guessed match.
class RegionResolution {
  /// Freezes the candidate list for the reported status.
  RegionResolution(this.status, Iterable<PlanarRegion> candidates)
    : candidates = List.unmodifiable(candidates);

  /// The resolution outcome.
  final RegionResolutionStatus status;

  /// All matching current regions; a resolved outcome has exactly one.
  final List<PlanarRegion> candidates;
}
