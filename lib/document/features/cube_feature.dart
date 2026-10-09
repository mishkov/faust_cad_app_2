import '../../cad_scene/cad_objects/cube.dart';
import '../../cad_scene/cad_primitivies/vertex.dart';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../feature_definition.dart';
import '../feature_evaluation_context.dart';
import '../feature_output.dart';
import '../output_reference.dart';

final class CubeFeature {
  static const type = 'cube';
  static List<FeatureOutput> evaluate(
    FeatureDefinition definition,
    FeatureEvaluationContext context,
  ) {
    double number(String key) {
      final value = definition.parameters[key];
      if (value is! num || !value.isFinite) {
        throw ArgumentError('Cube requires finite $key');
      }
      return value.toDouble();
    }

    final size = number('size');
    if (size <= 0) throw ArgumentError('Cube size must be positive');
    final cube = Cube(
      centerPosition: Vertex(Vector3(number('x'), number('y'), number('z'))),
      size: size,
    ).buildGeometry();
    return [
      FeatureOutput(key: 'body', kind: OutputKind.body, geometry: cube.body),
      for (final entry in cube.planarFaces.entries)
        FeatureOutput(
          key: entry.key,
          kind: OutputKind.planarFace,
          geometry: entry.value,
        ),
    ];
  }
}
