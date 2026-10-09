import 'feature_output.dart';
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
}

final class FeatureResult {
  FeatureResult({
    required this.state,
    List<FeatureOutput> outputs = const [],
    this.issue,
    this.support,
    this.message,
    List<FeatureOutput> diagnosticOutputs = const [],
  }) : outputs = List.unmodifiable(
         state == FeatureState.valid ? outputs : <FeatureOutput>[],
       ),
       diagnosticOutputs = List.unmodifiable(diagnosticOutputs);

  final ResolvedPlanarSupport? support;
  final FeatureState state;
  final List<FeatureOutput> outputs;
  final FeatureIssue? issue;
  final String? message;
  final List<FeatureOutput> diagnosticOutputs;
}
