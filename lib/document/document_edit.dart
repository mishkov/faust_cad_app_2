import 'feature_definition.dart';
import 'feature_id.dart';

/// An isolated draft for one atomic document command.
///
/// Changes publish only after the controller's callback returns successfully.
/// Retaining or changing this draft later cannot change the document or history.
final class DocumentEdit {
  DocumentEdit(List<FeatureDefinition> features)
    : _features = List.of(features);

  List<FeatureDefinition> _features;

  /// The current definitions in document order.
  List<FeatureDefinition> get features => List.unmodifiable(_features);

  /// Adds a definition with a new stable ID.
  ///
  /// Throws an [ArgumentError] if the ID already exists.
  void addFeature(FeatureDefinition feature) {
    if (_features.any((existing) => existing.id == feature.id)) {
      throw ArgumentError('Duplicate feature ID: ${feature.id}');
    }
    _features.add(feature);
  }

  /// Adds or replaces a definition while preserving existing document order.
  void setFeature(FeatureDefinition feature) {
    final index = _features.indexWhere((existing) => existing.id == feature.id);
    if (index < 0) {
      _features.add(feature);
    } else {
      _features[index] = feature;
    }
  }

  /// Removes a definition without deleting its dependents.
  ///
  /// Throws an [ArgumentError] if [id] does not exist. Remaining references are
  /// evaluated by the document and may report failed or blocked states.
  void removeFeature(FeatureId id) {
    _requireFeature(id);
    _features.removeWhere((feature) => feature.id == id);
  }

  /// Merges parameter values into an existing definition.
  ///
  /// Preserves its ID, type, dependencies, and semantic input references.
  /// Throws an [ArgumentError] for a missing ID or unsupported parameter value.
  /// Geometric validity is determined later by the evaluator.
  void updateParameters(FeatureId id, Map<String, Object?> values) {
    final feature = _requireFeature(id);
    setFeature(
      FeatureDefinition(
        id: feature.id,
        type: feature.type,
        parameters: {...feature.parameters, ...values},
        dependencies: feature.dependencies,
        inputs: feature.inputs,
      ),
    );
  }

  /// Replaces the draft with a complete, ordered set of definitions.
  ///
  /// Throws an [ArgumentError] for duplicate IDs without changing the draft.
  void replaceFeatures(List<FeatureDefinition> features) {
    final ids = <FeatureId>{};
    for (final feature in features) {
      if (!ids.add(feature.id)) {
        throw ArgumentError('Duplicate feature ID: ${feature.id}');
      }
    }
    _features = List.of(features);
  }

  FeatureDefinition _requireFeature(FeatureId id) => _features.firstWhere(
    (feature) => feature.id == id,
    orElse: () => throw ArgumentError('Unknown feature ID: $id'),
  );
}
