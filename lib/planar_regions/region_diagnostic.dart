/// A machine-readable condition discovered while building or selecting regions.
class RegionDiagnostic {
  /// Creates a diagnostic tied to the affected input identities.
  RegionDiagnostic(
    this.code,
    this.message,
    Iterable<String> inputIds, {
    this.isError = false,
  }) : inputIds = List.unmodifiable(inputIds);

  /// A stable code documented in docs/planar_regions.md.
  final String code;

  /// A human-readable explanation.
  final String message;

  /// The affected input IDs in stable order.
  final List<String> inputIds;

  /// Whether this condition prevents publishing a usable result.
  final bool isError;
}
