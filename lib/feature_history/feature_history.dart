import 'dart:convert';

import '../document/feature_definition.dart';
import '../document/output_reference.dart';
import '../document/feature_id.dart';
import '../document/features/cube_feature.dart';
import '../document/features/extrude_feature.dart';
import '../document/features/sketch_feature.dart';

final class FeatureHistory {
  static String typeName(String type) => switch (type) {
    CubeFeature.type => 'Cube',
    SketchFeature.type => 'Sketch',
    ExtrudeFeature.type => 'Extrusion',
    _ => type,
  };

  static String name(FeatureDefinition feature) =>
      feature.name ?? '${typeName(feature.type)} (${feature.id.value})';

  static String referenceLabel(
    OutputReference reference,
    List<FeatureDefinition> features,
  ) {
    final producer = features
        .where((f) => f.id == reference.featureId)
        .firstOrNull;
    var key = reference.key;
    try {
      final decoded = jsonDecode(key);
      if (decoded is List &&
          decoded.length == 5 &&
          decoded[0] == 'extrusion-lineage' &&
          decoded[1] == 1) {
        key = switch (decoded[3]) {
          'startCap' => 'Start cap',
          'endCap' => 'End cap',
          'wall' => 'Wall',
          'body' => 'Body',
          _ => key,
        };
      }
    } on FormatException {
      // Most semantic output keys are ordinary strings.
    }
    return '${producer == null ? reference.featureId : name(producer)} / $key';
  }

  static List<FeatureDefinition> affectedDependents(
    List<FeatureDefinition> features,
    FeatureId id,
  ) {
    final affected = {id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final feature in features) {
        if (feature.dependencies.any(affected.contains) &&
            affected.add(feature.id)) {
          changed = true;
        }
      }
    }
    return features
        .where((f) => f.id != id && affected.contains(f.id))
        .toList();
  }
}
