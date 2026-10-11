import '../../sketch/sketch_definition.dart';
import '../../sketch/sketch_geometry.dart';
import '../feature_definition.dart';
import '../feature_evaluation_context.dart';
import '../feature_id.dart';
import '../feature_output.dart';

/// Publishes an unconstrained sketch as independent non-topological geometry.
final class SketchFeature {
  static const type = 'sketch';
  static const outputKey = 'sketch';
  static const parameterKey = 'sketch';

  /// Creates a document-owned value definition, including its support dependency.
  static FeatureDefinition definition({
    required FeatureId id,
    required SketchDefinition sketch,
  }) => FeatureDefinition(
    id: id,
    type: type,
    support: sketch.support,
    parameters: {parameterKey: sketch.toParameters()},
  );

  /// Reads the current authored values from a feature definition.
  static SketchDefinition readDefinition(FeatureDefinition definition) {
    if (definition.type != type || definition.support == null) {
      throw ArgumentError('Sketch requires a sketch type and planar support');
    }
    return SketchDefinition.fromParameters(
      support: definition.support!,
      parameters: definition.parameters[parameterKey],
    );
  }

  /// Places validated local entities on the support resolved by feature history.
  static List<FeatureOutput> evaluate(
    FeatureDefinition definition,
    FeatureEvaluationContext context,
  ) {
    final sketch = readDefinition(definition);
    final support = context.support;
    if (support == null) throw StateError('Sketch support is unresolved');
    return [
      FeatureOutput.sketch(
        key: outputKey,
        data: SketchGeometry(definition: sketch, frame: support.frame),
      ),
    ];
  }
}
