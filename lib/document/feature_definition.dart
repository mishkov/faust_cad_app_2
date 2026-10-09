import 'package:equatable/equatable.dart';

import 'feature_id.dart';
import 'output_reference.dart';

// Definitions contain only value data, never topology or mutable vectors.
final class FeatureDefinition extends Equatable {
  FeatureDefinition({
    required this.id,
    required this.type,
    Map<String, Object?> parameters = const {},
    Set<FeatureId> dependencies = const {},
    Map<String, OutputReference> inputs = const {},
  }) : parameters = Map.unmodifiable(
         parameters.map((k, v) => MapEntry(k, _freeze(v))),
       ),
       inputs = Map.unmodifiable(inputs),
       dependencies = Set.unmodifiable({
         ...dependencies,
         ...inputs.values.map((r) => r.featureId),
       }) {
    if (type.isEmpty) throw ArgumentError('Feature type must not be empty');
  }

  final FeatureId id;
  final String type;
  final Map<String, Object?> parameters;
  final Set<FeatureId> dependencies;
  final Map<String, OutputReference> inputs;

  @override
  List<Object> get props => [id, type, parameters, dependencies, inputs];
}

Object? _freeze(Object? value) => switch (value) {
  null || String() || bool() || int() => value,
  double() when value.isFinite => value,
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k, _freeze(v))),
  ),
  _ => throw ArgumentError(
    'Parameters must be finite scalar, list, or string-keyed map values',
  ),
};
