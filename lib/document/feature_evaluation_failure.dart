import 'feature_result.dart';
import 'src/immutable_value.dart';

/// An evaluator failure with structured immutable diagnostics for inspection.
final class FeatureEvaluationFailure implements Exception {
  FeatureEvaluationFailure({
    required this.message,
    this.issue = FeatureIssue.evaluationFailed,
    Map<String, Object?> diagnostics = const {},
  }) : diagnostics = freezeValue(diagnostics) as Map<String, Object?>;
  final String message;
  final FeatureIssue issue;
  final Map<String, Object?> diagnostics;
  @override
  String toString() => message;
}
