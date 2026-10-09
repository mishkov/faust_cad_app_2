import 'dart:convert';

import 'planar_region.dart';
import 'region_diagnostic.dart';
import 'region_reference.dart';
import 'region_resolution.dart';
import 'region_selection.dart';
import 'region_loop.dart';

/// An immutable selectable arrangement and its diagnostics.
class RegionResult {
  /// Freezes the arrangement's regions and installs its analytic union operation.
  RegionResult({
    required Iterable<PlanarRegion> regions,
    required Iterable<RegionDiagnostic> diagnostics,
    required this._select,
  }) : regions = List.unmodifiable(regions),
       diagnostics = List.unmodifiable(diagnostics);
  final RegionSelection Function(Set<String>) _select;

  /// The bounded atomic material cells, in deterministic order.
  final List<PlanarRegion> regions;

  /// Degeneracies, open boundaries, and numerical failures discovered by the engine.
  final List<RegionDiagnostic> diagnostics;

  /// Whether the arrangement is usable; warnings do not invalidate bounded cells.
  bool get isValid => !diagnostics.any((d) => d.isError);

  /// Unites arrangement-local cells, preserving separate components and holes.
  ///
  /// Duplicate IDs are idempotent. Unknown IDs throw [ArgumentError]. Point-only
  /// connectivity returns an invalid selection with no material components.
  RegionSelection union(Iterable<String> regionIds) {
    final ids = regionIds.toSet();
    if (!ids.every((id) => regions.any((r) => r.id == id))) {
      throw ArgumentError('Selection contains an unknown region ID');
    }
    if (!isValid) {
      return RegionSelection([], diagnostics.where((d) => d.isError));
    }
    return _select(ids);
  }

  /// Captures a semantic reference to a current arrangement-local region.
  RegionReference reference(String regionId) {
    final region = regions.where((r) => r.id == regionId).firstOrNull;
    if (region == null) throw ArgumentError.value(regionId, 'regionId');
    return RegionReference(this, regionId, semanticSignature(region));
  }

  /// Resolves exact snapshot identity or conservative boundary lineage after edits.
  ///
  /// Edited inputs match only identical outer/hole source-ID sets. Multiple
  /// candidates are ambiguous. There is no nearest-point or index fallback.
  RegionResolution resolve(RegionReference reference) {
    if (!isValid) {
      return RegionResolution(RegionResolutionStatus.unavailable, []);
    }
    final candidates = identical(reference.owner, this)
        ? regions.where((r) => r.id == reference.regionId).toList()
        : regions
              .where((r) => semanticSignature(r) == reference.signature)
              .toList();
    return RegionResolution(
      candidates.isEmpty
          ? RegionResolutionStatus.missing
          : candidates.length == 1
          ? RegionResolutionStatus.resolved
          : RegionResolutionStatus.ambiguous,
      candidates,
    );
  }

  /// Encodes boundary source sets independently of coordinates and list ordering.
  static String semanticSignature(PlanarRegion region) {
    String sources(RegionLoop loop) => jsonEncode(
      loop.portions
          .expand((e) => e.sources.map((s) => s.inputId))
          .toSet()
          .toList()
        ..sort(),
    );
    return jsonEncode([
      sources(region.outer),
      region.holes.map(sources).toList()..sort(),
    ]);
  }
}
