import 'boundary_portion.dart';

/// One directed authored boundary between semantic junctions, ignoring seams.
final class BoundarySpan {
  /// Freezes the analytic patches belonging to one semantic span.
  BoundarySpan(this.key, Iterable<BoundaryPortion> portions)
    : portions = List.unmodifiable(portions);

  /// The canonical directed source and junction signature.
  final String key;

  /// All analytic patches; several patches do not identify one attachable face.
  final List<BoundaryPortion> portions;
}
