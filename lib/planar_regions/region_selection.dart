import 'planar_region.dart';
import 'region_diagnostic.dart';

/// The material union of selected cells, or explicit selection diagnostics.
class RegionSelection {
  /// Freezes material components and diagnostics.
  RegionSelection(
    Iterable<PlanarRegion> regions,
    Iterable<RegionDiagnostic> diagnostics,
  ) : regions = List.unmodifiable(regions),
      diagnostics = List.unmodifiable(diagnostics);

  /// Separate material components, each retaining its holes and analytic portions.
  final List<PlanarRegion> regions;

  /// Selection conditions, including rejected non-manifold point connections.
  final List<RegionDiagnostic> diagnostics;

  /// Whether selection produced usable material.
  bool get isValid => !diagnostics.any((d) => d.isError);
}
