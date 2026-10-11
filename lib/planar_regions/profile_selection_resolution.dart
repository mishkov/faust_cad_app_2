import 'planar_region.dart';
import 'region_reference.dart';
import 'region_resolution.dart';
import 'region_selection.dart';

/// An atomic selection resolution that exposes material only after full success.
final class ProfileSelectionResolution {
  /// Freezes cell outcomes and successful material correspondence.
  ProfileSelectionResolution(
    this.status,
    Iterable<RegionResolution> resolutions, {
    Iterable<PlanarRegion> regions = const [],
    this.material,
  }) : resolutions = List.unmodifiable(resolutions),
       regions = List.unmodifiable(regions);

  /// The combined outcome, including unusable unions as unavailable.
  final RegionResolutionStatus status;

  /// The per-cell outcomes, retaining every ambiguous candidate.
  final List<RegionResolution> resolutions;

  /// Current atomic cells, empty if any reference or the union is unresolved.
  final List<PlanarRegion> regions;

  /// The validated material union, present only for resolved selections.
  final RegionSelection? material;
}
