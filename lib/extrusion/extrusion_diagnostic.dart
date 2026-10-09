/// A structured rejection or upstream planar-region warning.
class ExtrusionDiagnostic {
  /// Freezes the affected region and source identities.
  ExtrusionDiagnostic(
    this.code,
    this.message, {
    this.isError = true,
    Iterable<String> regionIds = const [],
    Iterable<String> inputIds = const [],
  }) : regionIds = List.unmodifiable(regionIds),
       inputIds = List.unmodifiable(inputIds);

  /// The stable diagnostic code documented in docs/analytic_extrusion.md.
  final String code;

  /// The explanation of the condition.
  final String message;

  /// Whether the condition prevents publishing material.
  final bool isError;

  /// The affected arrangement-local selection identities.
  final List<String> regionIds;

  /// The affected original planar input identities.
  final List<String> inputIds;
}
