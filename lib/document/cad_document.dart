import 'evaluation_snapshot.dart';
import 'feature_definition.dart';
import 'feature_evaluation_context.dart';
import 'feature_id.dart';
import 'feature_output.dart';
import 'feature_result.dart';
import 'reference_resolution.dart';

final class CadDocument {
  CadDocument({
    required Map<String, FeatureEvaluator> evaluators,
    List<FeatureDefinition> features = const [],
  }) : _evaluators = Map.unmodifiable(evaluators) {
    replaceFeatures(features);
  }

  final Map<String, FeatureEvaluator> _evaluators;
  Map<FeatureId, FeatureDefinition> _definitions = const {};
  EvaluationSnapshot _evaluation = EvaluationSnapshot(
    revision: 0,
    features: const {},
    evaluationOrder: const [],
    rebuiltFeatures: const {},
  );
  bool _evaluating = false;

  List<FeatureDefinition> get features =>
      List.unmodifiable(_definitions.values);
  EvaluationSnapshot get evaluation => _evaluation;

  EvaluationSnapshot setFeature(FeatureDefinition feature) => replaceFeatures([
    for (final existing in features)
      if (existing.id != feature.id) existing,
    feature,
  ]);

  EvaluationSnapshot removeFeature(FeatureId id) => replaceFeatures([
    for (final feature in features)
      if (feature.id != id) feature,
  ]);

  // Useful for external evaluator inputs. Normal edits invalidate by value.
  EvaluationSnapshot rebuild(Set<FeatureId> ids) =>
      replaceFeatures(features, invalidate: ids);

  // Definitions and evaluation publish together only after the entire pass.
  EvaluationSnapshot replaceFeatures(
    List<FeatureDefinition> features, {
    Set<FeatureId> invalidate = const {},
  }) {
    if (_evaluating) throw StateError('Document evaluation is not reentrant');
    final next = <FeatureId, FeatureDefinition>{};
    for (final feature in features) {
      if (next.containsKey(feature.id)) {
        throw ArgumentError('Duplicate feature ID: ${feature.id}');
      }
      next[feature.id] = feature;
    }
    _evaluating = true;
    try {
      final result = _evaluate(next, invalidate);
      _definitions = Map.unmodifiable(next);
      _evaluation = result;
      return result;
    } finally {
      _evaluating = false;
    }
  }

  EvaluationSnapshot _evaluate(
    Map<FeatureId, FeatureDefinition> next,
    Set<FeatureId> invalidate,
  ) {
    final dirty = <FeatureId>{
      ...invalidate,
      for (final id in {...next.keys, ..._definitions.keys})
        if (next[id] != _definitions[id]) id,
    };
    final dependents = <FeatureId, Set<FeatureId>>{};
    for (final feature in next.values) {
      for (final dependency in feature.dependencies) {
        (dependents[dependency] ??= {}).add(feature.id);
      }
    }
    final pending = dirty.toList();
    while (pending.isNotEmpty) {
      for (final descendant
          in dependents[pending.removeLast()] ?? <FeatureId>{}) {
        if (dirty.add(descendant)) pending.add(descendant);
      }
    }
    List<FeatureId> sorted(Iterable<FeatureId> ids) =>
        ids.toList()..sort((a, b) => a.value.compareTo(b.value));
    // Tarjan components identify every cycle member, including overlapping loops.
    // Components are emitted after their dependencies; IDs break traversal ties.
    final indices = <FeatureId, int>{};
    final low = <FeatureId, int>{};
    final stack = <FeatureId>[];
    final active = <FeatureId>{};
    final cycles = <FeatureId>{};
    final order = <FeatureId>[];
    void visit(FeatureId id) {
      indices[id] = low[id] = indices.length;
      stack.add(id);
      active.add(id);
      for (final dependency in sorted(
        next[id]!.dependencies.where(next.containsKey),
      )) {
        if (!indices.containsKey(dependency)) {
          visit(dependency);
          if (low[dependency]! < low[id]!) low[id] = low[dependency]!;
        } else if (active.contains(dependency) &&
            indices[dependency]! < low[id]!) {
          low[id] = indices[dependency]!;
        }
      }
      if (low[id] != indices[id]) return;
      final component = <FeatureId>[];
      FeatureId member;
      do {
        member = stack.removeLast();
        active.remove(member);
        component.add(member);
      } while (member != id);
      if (component.length > 1 || next[id]!.dependencies.contains(id)) {
        cycles.addAll(component);
      }
      order.addAll(sorted(component));
    }

    for (final id in sorted(next.keys)) {
      if (!indices.containsKey(id)) visit(id);
    }
    final results = <FeatureId, FeatureResult>{};
    FeatureResult invalid(
      FeatureId id,
      FeatureState state,
      FeatureIssue issue,
      String message,
    ) {
      final previous = _evaluation.features[id];
      return FeatureResult(
        state: state,
        issue: issue,
        message: message,
        diagnosticOutputs: previous == null
            ? const []
            : previous.state == FeatureState.valid
            ? previous.outputs
            : previous.diagnosticOutputs,
      );
    }

    for (final id in cycles) {
      results[id] = invalid(
        id,
        FeatureState.failed,
        FeatureIssue.cycle,
        'Dependency cycle involving $id',
      );
    }
    for (final id in order) {
      if (cycles.contains(id)) continue;
      final feature = next[id]!;
      if (!dirty.contains(id) && _evaluation.features.containsKey(id)) {
        results[id] = _evaluation.features[id]!;
        continue;
      }
      final missing = sorted(
        feature.dependencies.where((dep) => !next.containsKey(dep)),
      );
      if (missing.isNotEmpty) {
        results[id] = invalid(
          id,
          FeatureState.failed,
          FeatureIssue.missingDependency,
          'Missing dependencies: ${missing.join(', ')}',
        );
        continue;
      }
      final unavailable = sorted(
        feature.dependencies.where(
          (dep) => results[dep]!.state != FeatureState.valid,
        ),
      );
      if (unavailable.isNotEmpty) {
        results[id] = invalid(
          id,
          FeatureState.blocked,
          FeatureIssue.unavailableDependency,
          'Unavailable dependencies: ${unavailable.join(', ')}',
        );
        continue;
      }
      final inputs = <String, FeatureOutput>{};
      FeatureResult? inputFailure;
      final partial = EvaluationSnapshot(
        revision: _evaluation.revision + 1,
        features: results,
        evaluationOrder: const [],
        rebuiltFeatures: const {},
      );
      for (final name in feature.inputs.keys.toList()..sort()) {
        final resolution = partial.resolve(feature.inputs[name]!);
        if (resolution.status != ReferenceStatus.resolved) {
          inputFailure = invalid(
            id,
            FeatureState.failed,
            resolution.status == ReferenceStatus.ambiguous
                ? FeatureIssue.ambiguousOutput
                : FeatureIssue.missingOutput,
            '${resolution.status.name} output for input $name',
          );
          break;
        }
        inputs[name] = resolution.output!;
      }
      if (inputFailure != null) {
        results[id] = inputFailure;
        continue;
      }
      try {
        final evaluator = _evaluators[feature.type];
        if (evaluator == null) {
          throw UnsupportedError('Unknown feature type: ${feature.type}');
        }
        final outputs = evaluator(
          feature,
          FeatureEvaluationContext(
            inputs: inputs,
            dependencies: {
              for (final dep in feature.dependencies) dep: results[dep]!,
            },
          ),
        );
        results[id] = FeatureResult(
          state: FeatureState.valid,
          outputs: outputs,
        );
      } catch (error) {
        results[id] = invalid(
          id,
          FeatureState.failed,
          FeatureIssue.evaluationFailed,
          error.toString(),
        );
      }
    }
    return EvaluationSnapshot(
      revision: _evaluation.revision + 1,
      features: {for (final id in order) id: results[id]!},
      evaluationOrder: order,
      rebuiltFeatures: dirty.intersection(next.keys.toSet()),
    );
  }
}
