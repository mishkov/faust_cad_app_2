import 'dart:convert';

import 'planar_region.dart';
import 'region_diagnostic.dart';
import 'region_reference.dart';
import 'region_resolution.dart';
import 'region_selection.dart';
import 'region_loop.dart';
import 'profile_capture.dart';
import 'profile_lineage.dart';
import 'profile_reference.dart';
import 'profile_selection_reference.dart';
import 'profile_selection_resolution.dart';

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

  /// Captures a unique directed profile identity for document storage.
  ProfileCapture captureProfile(String regionId, {required String sourceId}) {
    if (!isValid) {
      return const ProfileCapture(RegionResolutionStatus.unavailable);
    }
    final cell = regions.where((r) => r.id == regionId).firstOrNull;
    if (cell == null) {
      return const ProfileCapture(RegionResolutionStatus.missing);
    }
    final signature = ProfileLineage.signature(cell);
    if (signature == null) {
      return const ProfileCapture(RegionResolutionStatus.unavailable);
    }
    final reference = ProfileReference(
      sourceId: sourceId,
      signature: signature,
    );
    final resolution = resolveProfile(reference, sourceId: sourceId);
    return ProfileCapture(
      resolution.status,
      reference: resolution.status == RegionResolutionStatus.resolved
          ? reference
          : null,
    );
  }

  /// Resolves authored boundary relationships without snapshot or index fallback.
  RegionResolution resolveProfile(
    ProfileReference reference, {
    required String sourceId,
  }) {
    if (!isValid) {
      return RegionResolution(RegionResolutionStatus.unavailable, []);
    }
    if (sourceId != reference.sourceId) {
      return RegionResolution(RegionResolutionStatus.missing, []);
    }
    final signatures = {
      for (final r in regions) r: ProfileLineage.signature(r),
    };
    final sourceIds = reference.boundarySourceIds;
    if (signatures.entries.any((entry) {
      if (entry.value != null) return false;
      final ids = [entry.key.outer, ...entry.key.holes]
          .expand((l) => l.portions)
          .expand((p) => p.sources.map((s) => s.inputId))
          .toSet();
      return ids.isEmpty ||
          ids.length == sourceIds.length && ids.containsAll(sourceIds);
    })) {
      return RegionResolution(RegionResolutionStatus.unavailable, []);
    }
    final candidates = regions
        .where((r) => signatures[r] == reference.signature)
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

  /// Resolves all selected cells and their union atomically, never dropping one.
  ProfileSelectionResolution resolveProfiles(
    ProfileSelectionReference selection, {
    required String sourceId,
  }) {
    final outcomes = selection.references
        .map((r) => resolveProfile(r, sourceId: sourceId))
        .toList();
    for (final status in [
      RegionResolutionStatus.unavailable,
      RegionResolutionStatus.ambiguous,
      RegionResolutionStatus.missing,
    ]) {
      if (outcomes.any((r) => r.status == status)) {
        return ProfileSelectionResolution(status, outcomes);
      }
    }
    final cells = outcomes.map((r) => r.candidates.single).toList();
    final material = union(cells.map((r) => r.id));
    return material.isValid
        ? ProfileSelectionResolution(
            RegionResolutionStatus.resolved,
            outcomes,
            regions: cells,
            material: material,
          )
        : ProfileSelectionResolution(
            RegionResolutionStatus.unavailable,
            outcomes,
          );
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
