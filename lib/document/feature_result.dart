import 'feature_output.dart';
import 'src/immutable_value.dart';
import 'resolved_planar_support.dart';

enum FeatureState { valid, failed, blocked }

enum FeatureIssue {
  cycle,
  missingDependency,
  unavailableDependency,
  missingOutput,
  ambiguousOutput,
  evaluationFailed,
  brokenAttachment,
  constraintSolveFailed,
}

final class FeatureResult {
  FeatureResult({
    required this.state,
    List<FeatureOutput> outputs = const [],
    this.issue,
    this.support,
    this.message,
    Map<String, Object?> diagnostics = const {},
    List<FeatureOutput> diagnosticOutputs = const [],
  }) : diagnostics = freezeValue(diagnostics) as Map<String, Object?>,
       outputs = List.unmodifiable(
         state == FeatureState.valid ? outputs : <FeatureOutput>[],
       ),
       diagnosticOutputs = List.unmodifiable(diagnosticOutputs);

  final ResolvedPlanarSupport? support;
  final FeatureState state;
  final List<FeatureOutput> outputs;
  final FeatureIssue? issue;
  final String? message;
  final Map<String, Object?> diagnostics;
  final List<FeatureOutput> diagnosticOutputs;
}
