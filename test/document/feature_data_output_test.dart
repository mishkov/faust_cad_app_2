import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

void main() {
  test('generic data outputs freeze caller values at capture and every consumer boundary', () {
    final nested = <Object?>[
      1,
      <String, Object?>{'value': 2.0},
    ];
    final source = <String, Object?>{'nested': nested};
    final producer = FeatureId('producer');
    final consumer = FeatureId('consumer');
    final reference = OutputReference(
      featureId: producer,
      kind: OutputKind.data,
      key: 'data',
    );
    final doc = CadDocument(
      evaluators: {
        'producer': (d, c) => [FeatureOutput.data(key: 'data', data: source)],
        'consumer': (d, c) {
          final data = c.input('data').data as Map<String, Object?>;
          expect(c.dependencyOutputs(producer).single.data, same(data));
          expect(() => data.clear(), throwsUnsupportedError);
          expect(
            () => ((data['nested'] as List)[1] as Map)['value'] = 9,
            throwsUnsupportedError,
          );
          return [
            FeatureOutput.data(
              key: 'sum',
              data: (data['nested'] as List).first,
            ),
          ];
        },
      },
      features: [
        FeatureDefinition(id: producer, type: 'producer'),
        FeatureDefinition(
          id: consumer,
          type: 'consumer',
          inputs: {'data': reference},
        ),
      ],
    );
    source.clear();
    nested.clear();
    expect(doc.evaluation.resolve(reference).status, ReferenceStatus.resolved);
    expect(doc.evaluation.resolve(reference).output!.data, {
      'nested': [
        1,
        {'value': 2.0},
      ],
    });
    expect(doc.evaluation.features[consumer]!.outputs.single.data, 1);
    expect(doc.evaluation.dataOutputs, hasLength(2));
    expect(() => doc.evaluation.dataOutputs.clear(), throwsUnsupportedError);
    expect(doc.evaluation.geometry, isEmpty);
    expect(doc.evaluation.materializeGeometry().geometry, isEmpty);
    final before = doc.evaluation;
    doc.setFeature(
      FeatureDefinition(
        id: producer,
        type: 'producer',
        parameters: {'revision': 1},
      ),
    );
    expect(doc.evaluation.resolve(reference).output!.data, isEmpty);
    expect(doc.evaluation.features[consumer]!.state, FeatureState.failed);
    expect(before.resolve(reference).output!.data, {
      'nested': [
        1,
        {'value': 2.0},
      ],
    });
  });

  test(
    'generic data rejects unsupported mutable objects and nonfinite values',
    () {
      for (final invalid in [
        Vector2.zero(),
        double.nan,
        double.infinity,
        <int, Object?>{1: 2},
        {
          'nested': [Vector2.zero()],
        },
      ]) {
        expect(
          () => FeatureOutput.data(key: 'data', data: invalid),
          throwsArgumentError,
        );
      }
      expect(
        () => FeatureOutput.data(key: '', data: null),
        throwsArgumentError,
      );
      expect(FeatureOutput.data(key: 'null', data: null).data, isNull);
    },
  );
}
