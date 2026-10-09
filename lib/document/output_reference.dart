import 'package:equatable/equatable.dart';

import 'feature_id.dart';

enum OutputKind { body, planarFace, face }

final class OutputReference extends Equatable {
  OutputReference({
    required this.featureId,
    required this.key,
    required this.kind,
  }) {
    if (key.isEmpty) throw ArgumentError('Output key must not be empty');
  }

  final FeatureId featureId;
  final String key;
  final OutputKind kind;
  @override
  List<Object> get props => [featureId, key, kind];
}
