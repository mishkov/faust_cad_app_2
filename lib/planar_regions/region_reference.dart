/// The outcome of resolving semantic boundary provenance after an input edit.
enum RegionResolutionStatus { resolved, missing, ambiguous, unavailable }

/// A conservative semantic reference retaining outer and hole source identities.
class RegionReference {
  /// Creates a reference to a region produced by an engine result.
  RegionReference(this.owner, this.regionId, this.signature);

  /// The originating immutable arrangement, used only for exact snapshot resolution.
  final Object owner;

  /// The arrangement-local region identity.
  final String regionId;

  /// The semantic boundary signature; coordinates and proximity are excluded.
  final String signature;
}
