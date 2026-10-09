import '../cad_scene/cad_primitivies/cad_primitive.dart';
import '../cad_scene/cad_primitivies/face.dart';

import 'feature_id.dart';
import 'evaluated_geometry.dart';
import 'feature_result.dart';
import 'output_reference.dart';
import 'reference_resolution.dart';

final class EvaluationSnapshot {
  EvaluationSnapshot({
    required this.revision,
    required Map<FeatureId, FeatureResult> features,
    required List<FeatureId> evaluationOrder,
    required Set<FeatureId> rebuiltFeatures,
  }) : features = Map.unmodifiable(features),
       evaluationOrder = List.unmodifiable(evaluationOrder),
       rebuiltFeatures = Set.unmodifiable(rebuiltFeatures);

  final int revision;
  final Map<FeatureId, FeatureResult> features;
  final List<FeatureId> evaluationOrder;
  final Set<FeatureId> rebuiltFeatures;

  ReferenceResolution resolve(OutputReference reference) {
    final feature = features[reference.featureId];
    if (feature == null) {
      return const ReferenceResolution(ReferenceStatus.missing);
    }
    if (feature.state != FeatureState.valid) {
      return const ReferenceResolution(ReferenceStatus.unavailable);
    }
    final matches = feature.outputs
        .where((o) => o.key == reference.key && o.kind == reference.kind)
        .toList();
    if (matches.isEmpty) {
      return const ReferenceResolution(ReferenceStatus.missing);
    }
    if (matches.length > 1) {
      return ReferenceResolution(
        ReferenceStatus.ambiguous,
        candidateCount: matches.length,
      );
    }
    return ReferenceResolution(
      ReferenceStatus.resolved,
      output: matches.single,
      candidateCount: 1,
    );
  }

  EvaluatedGeometry materializeGeometry() {
    final geometry = <CadPrimitive>[];
    final bodies = <CadPrimitive, OutputReference>{};
    final faces = <Face, OutputReference>{};
    for (final entry in features.entries) {
      if (entry.value.state != FeatureState.valid) continue;
      for (final output in entry.value.outputs) {
        if (output.kind != OutputKind.body) continue;
        final materialized = output.materialize();
        geometry.add(materialized.geometry);
        final bodyReference = OutputReference(
          featureId: entry.key,
          key: output.key,
          kind: output.kind,
        );
        if (resolve(bodyReference).status == ReferenceStatus.resolved) {
          bodies[materialized.geometry] = bodyReference;
        }
        for (final face in materialized.faceKeys.entries) {
          final matches = entry.value.outputs.where(
            (o) =>
                o.key == face.value &&
                (o.kind == OutputKind.planarFace || o.kind == OutputKind.face),
          );
          // Ambiguous names remain unattachable; picking never guesses a key.
          if (matches.length != 1) continue;
          final reference = OutputReference(
            featureId: entry.key,
            key: face.value,
            kind: matches.single.kind,
          );
          if (resolve(reference).status == ReferenceStatus.resolved) {
            faces[face.key] = reference;
          }
        }
      }
    }
    return EvaluatedGeometry(geometry: geometry, bodies: bodies, faces: faces);
  }

  // Semantic faces are attachments, not extra surfaces to draw over their body.
  List<CadPrimitive> get geometry => List.unmodifiable([
    for (final result in features.values)
      for (final output in result.outputs)
        if (output.kind == OutputKind.body) output.geometry,
  ]);
}
