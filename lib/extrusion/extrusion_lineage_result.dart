import '../document/feature_id.dart';
import '../document/feature_output.dart';
import '../document/output_reference.dart';
import '../document/reference_resolution.dart';
import 'extrusion_face_output.dart';
import 'extrusion_result.dart';

/// Semantic document outputs and explicit unavailable extrusion correspondence.
final class ExtrusionLineageResult {
  /// Freezes justified outputs and rejected names, retaining the source result.
  ExtrusionLineageResult({
    required this.featureId,
    required this.extrusion,
    required Iterable<FeatureOutput> outputs,
    required Map<(String, OutputKind), int> ambiguousKeys,
    required Iterable<ExtrusionFaceOutput> unavailableFaces,
    this.hasUnsupportedCorrespondence = false,
  }) : outputs = List.unmodifiable(outputs),
       ambiguousKeys = Map.unmodifiable(ambiguousKeys),
       unavailableFaces = List.unmodifiable(unavailableFaces);

  /// The authored extrusion producer's stable document identity.
  final FeatureId featureId;

  /// The original analytic geometry, including any unnamed faces or bodies.
  final ExtrusionResult extrusion;

  /// Unique justified body/face outputs, ready for a feature evaluator to publish.
  final List<FeatureOutput> outputs;

  /// Semantic names shared by multiple candidates; none are attachment outputs.
  final Map<(String, OutputKind), int> ambiguousKeys;

  /// Faces without one justified semantic identity, including subdivided arcs.
  final List<ExtrusionFaceOutput> unavailableFaces;

  /// Whether some output lacks supported correspondence rather than a known key.
  final bool hasUnsupportedCorrespondence;

  /// The published references; unavailable patches never receive one.
  List<OutputReference> get references => List.unmodifiable(
    outputs.map(
      (o) => OutputReference(featureId: featureId, key: o.key, kind: o.kind),
    ),
  );

  /// Resolves a semantic output with no patch-index or operation-key fallback.
  ReferenceResolution resolve(OutputReference reference) {
    if (reference.featureId != featureId) {
      return const ReferenceResolution(ReferenceStatus.missing);
    }
    if (!extrusion.isValid) {
      return const ReferenceResolution(ReferenceStatus.unavailable);
    }
    final count = ambiguousKeys[(reference.key, reference.kind)];
    if (count != null) {
      return ReferenceResolution(
        ReferenceStatus.ambiguous,
        candidateCount: count,
      );
    }
    final matches = outputs.where(
      (o) => o.key == reference.key && o.kind == reference.kind,
    );
    if (matches.isEmpty) {
      return ReferenceResolution(
        hasUnsupportedCorrespondence
            ? ReferenceStatus.unavailable
            : ReferenceStatus.missing,
      );
    }
    return ReferenceResolution(
      ReferenceStatus.resolved,
      output: matches.single,
      candidateCount: 1,
    );
  }
}
