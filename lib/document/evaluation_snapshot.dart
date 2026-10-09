import '../cad_scene/cad_primitivies/cad_primitive.dart';
import 'feature_id.dart';
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

  // Semantic faces are attachments, not extra surfaces to draw over their body.
  List<CadPrimitive> get geometry => List.unmodifiable([
    for (final result in features.values)
      for (final output in result.outputs)
        if (output.kind == OutputKind.body) output.geometry,
  ]);
}
