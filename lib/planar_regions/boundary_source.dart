/// A directed parameter interval on an original input.
class BoundarySource {
  /// Creates an immutable provenance interval.
  const BoundarySource(this.inputId, this.startParameter, this.endParameter);

  /// The caller's original geometry identity.
  final String inputId;

  /// The parameter at the boundary portion's start.
  final double startParameter;

  /// The parameter at its end; reversed portions have descending intervals.
  ///
  /// Segments use [0, 1]. Circles use unwrapped radians; 2π can be an endpoint.
  final double endParameter;

  /// Returns provenance for traversal in the opposite direction.
  BoundarySource reversed() =>
      BoundarySource(inputId, endParameter, startParameter);
}
