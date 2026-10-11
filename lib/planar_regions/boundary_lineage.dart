/// Authored junction lineage at the ends of an analytic boundary portion.
final class BoundaryLineage {
  /// Records canonical endpoint/intersection events; `null` denotes a seam.
  const BoundaryLineage({required this.start, required this.end});

  /// The start junction's event signature, excluding coordinates and parameters.
  final String? start;

  /// The end junction's event signature, excluding coordinates and parameters.
  final String? end;
}
