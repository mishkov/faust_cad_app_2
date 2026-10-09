import 'feature_definition.dart';
import 'feature_id.dart';
import 'feature_output.dart';
import 'feature_result.dart';
import 'resolved_planar_support.dart';

final class FeatureEvaluationContext {
  FeatureEvaluationContext({
    this.support,
    required Map<String, FeatureOutput> inputs,
    required Map<FeatureId, FeatureResult> dependencies,
  }) : _inputs = Map.unmodifiable(inputs),
       _dependencies = Map.unmodifiable(dependencies);

  final ResolvedPlanarSupport? support;
  final Map<String, FeatureOutput> _inputs;
  final Map<FeatureId, FeatureResult> _dependencies;

  FeatureOutput input(String name) =>
      _inputs[name] ?? (throw StateError('Undeclared input: $name'));
  List<FeatureOutput> dependencyOutputs(FeatureId id) =>
      _dependencies[id]?.outputs ??
      (throw StateError('Undeclared dependency: $id'));
}

typedef FeatureEvaluator = List<FeatureOutput> Function(
  FeatureDefinition definition,
  FeatureEvaluationContext context,
);
