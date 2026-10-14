import 'package:equatable/equatable.dart';

import 'feature_id.dart';
import 'output_reference.dart';
import 'planar_support.dart';
import 'src/immutable_value.dart';

// Definitions contain only value data, never topology or mutable vectors.
final class FeatureDefinition extends Equatable {
  FeatureDefinition({
    required this.id,
    required this.type,
    String? name,
    Map<String, Object?> parameters = const {},
    this.support,
    Set<FeatureId> dependencies = const {},
    Map<String, OutputReference> inputs = const {},
  }) : name = name?.trim(),
       parameters = Map.unmodifiable(
         parameters.map((k, v) => MapEntry(k, freezeValue(v))),
       ),
       inputs = Map.unmodifiable(inputs),
       dependencies = Set.unmodifiable({
         ...dependencies,
         if (support?.reference != null) support!.reference!.featureId,
         ...inputs.values.map((r) => r.featureId),
       }) {
    if (this.name != null && this.name!.isEmpty) {
      throw ArgumentError('Feature name must not be blank');
    }
    if (type.isEmpty) throw ArgumentError('Feature type must not be empty');
  }

  final PlanarSupport? support;
  final FeatureId id;
  final String type;
  final String? name;
  final Map<String, Object?> parameters;
  final Set<FeatureId> dependencies;
  final Map<String, OutputReference> inputs;

  @override
  List<Object> get props => [
    id,
    type,
    ?name,
    parameters,
    dependencies,
    inputs,
    ?support,
  ];
}
