import 'feature_output.dart';

enum ReferenceStatus { resolved, missing, ambiguous, unavailable }

final class ReferenceResolution {
  const ReferenceResolution(
    this.status, {
    this.output,
    this.candidateCount = 0,
  });
  final ReferenceStatus status;
  final FeatureOutput? output;
  final int candidateCount;
}
