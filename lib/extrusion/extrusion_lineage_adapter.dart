import 'dart:convert';

import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/cad_surfaces/plane_surface.dart';
import '../document/feature_id.dart';
import '../document/feature_output.dart';
import '../document/output_reference.dart';
import '../planar_regions/planar_regions.dart';
import 'extruded_volume.dart';
import 'extrusion_face_output.dart';
import 'extrusion_lineage_result.dart';
import 'extrusion_result.dart';

/// Assigns conservative semantic document outputs to analytic extrusion results.
final class ExtrusionLineageAdapter {
  /// Creates a stateless lineage adapter without registering a history feature.
  const ExtrusionLineageAdapter();

  /// Publishes only unique bodies, cap roles, and complete semantic wall spans.
  ///
  /// Several analytic patches for one wall span are ambiguous and unattachable.
  /// Distance, reverse, input permutation, seams, and tessellation are not names.
  ExtrusionLineageResult adapt({
    required FeatureId featureId,
    required String profileSourceId,
    required ExtrusionResult extrusion,
  }) {
    if (profileSourceId.isEmpty) {
      throw ArgumentError('Profile source ID must not be empty');
    }
    final bodies = <String, List<ExtrudedVolume>>{};
    final faces = <String, List<ExtrusionFaceOutput>>{};
    final faceNames = <ExtrusionFaceOutput, String>{};
    final unavailable = <ExtrusionFaceOutput>{};
    var unsupported = false;
    String key(String role, String lineage) =>
        jsonEncode(['extrusion-lineage', 1, profileSourceId, role, lineage]);
    for (final volume in extrusion.volumes) {
      final signature = ProfileLineage.signature(volume.profile);
      if (signature == null) {
        unsupported = true;
        unavailable.addAll(volume.faces);
        continue;
      }
      final bodyKey = key('body', signature);
      bodies.putIfAbsent(bodyKey, () => []).add(volume);
      final wallKeys = <BoundaryPortion, String>{};
      for (final loop in [volume.profile.outer, ...volume.profile.holes]) {
        for (final span in ProfileLineage.spans(loop)!) {
          for (final portion in span.portions) {
            wallKeys[portion] = key('wall', span.key);
          }
        }
      }
      for (final face in volume.faces) {
        final String? faceKey;
        if (face.role == ExtrusionFaceRole.wall) {
          // Exact snapshot provenance maps the generated patch to its semantic
          // span. Object identity is only an adapter lookup, never a stored name.
          faceKey = face.boundaries.length == 1
              ? wallKeys[face.boundaries.single]
              : null;
        } else {
          faceKey = key(face.role.name, signature);
        }
        if (faceKey == null) {
          unsupported = true;
          unavailable.add(face);
        } else {
          faceNames[face] = faceKey;
          faces.putIfAbsent(faceKey, () => []).add(face);
        }
      }
    }
    final ambiguous = <(String, OutputKind), int>{};
    for (final entry in bodies.entries) {
      if (entry.value.length > 1) {
        ambiguous[(entry.key, OutputKind.body)] = entry.value.length;
      }
    }
    for (final entry in faces.entries) {
      if (entry.value.length > 1) {
        ambiguous[(
              entry.key,
              entry.value.first.face.surface is PlaneSurface
                  ? OutputKind.planarFace
                  : OutputKind.face,
            )] =
            entry.value.length;
        unavailable.addAll(entry.value);
      }
    }
    final outputs = <FeatureOutput>[];
    for (final entry in bodies.entries) {
      if (entry.value.length != 1) {
        unavailable.addAll(entry.value.expand((v) => v.faces));
        continue;
      }
      final volume = entry.value.single;
      final named = <String, Face>{};
      for (final face in volume.faces) {
        final faceKey = faceNames[face];
        if (faceKey == null || unavailable.contains(face)) continue;
        named[faceKey] = face.face;
        outputs.add(
          FeatureOutput(
            key: faceKey,
            kind: face.face.surface is PlaneSurface
                ? OutputKind.planarFace
                : OutputKind.face,
            geometry: face.face,
          ),
        );
      }
      outputs.add(
        FeatureOutput(
          key: entry.key,
          kind: OutputKind.body,
          geometry: volume.solid,
          faceKeys: named,
        ),
      );
    }
    outputs.sort((a, b) => a.key.compareTo(b.key));
    return ExtrusionLineageResult(
      featureId: featureId,
      extrusion: extrusion,
      outputs: outputs,
      ambiguousKeys: ambiguous,
      unavailableFaces: unavailable,
      hasUnsupportedCorrespondence: unsupported,
    );
  }
}
