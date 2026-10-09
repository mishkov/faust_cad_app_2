import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/evaluation_snapshot.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_context.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test(
    'dependency order is deterministic and edits rebuild only descendants',
    () {
      final calls = <String>[];
      final doc = CadDocument(
        evaluators: {
          'cube': (d, c) {
            calls.add(d.id.value);
            return CubeFeature.evaluate(d, c);
          },
          'attached': (d, c) {
            calls.add(d.id.value);
            return _attached(d, c);
          },
        },
        features: [
          _attachedDefinition('c', 'b'),
          _cube('z'),
          _attachedDefinition('b', 'a'),
          _cube('a'),
        ],
      );
      expect(calls, ['a', 'b', 'c', 'z']);
      final before = doc.evaluation;
      final previousTop = _top(before, 'c');
      calls.clear();
      final after = doc.setFeature(_cube('a', size: 8));
      expect(calls, ['a', 'b', 'c']);
      expect(after.rebuiltFeatures, {
        FeatureId('a'),
        FeatureId('b'),
        FeatureId('c'),
      });
      expect(_top(after, 'c'), greaterThan(previousTop));
      expect(
        after.features[FeatureId('z')],
        same(before.features[FeatureId('z')]),
      );
      expect(_top(before, 'c'), previousTop);
      calls.clear();
      doc.replaceFeatures(doc.features.reversed.toList());
      expect(calls, isEmpty);
      expect(doc.evaluation.evaluationOrder, before.evaluationOrder);
    },
  );

  test('diamond dependency evaluates each shared descendant once', () {
    final calls = <String>[];
    final doc = CadDocument(
      evaluators: {
        'node': (d, c) {
          calls.add(d.id.value);
          return [];
        },
      },
      features: [
        _node('d', ['b', 'c']),
        _node('c', ['a']),
        _node('b', ['a']),
        _node('a'),
      ],
    );
    expect(calls, ['a', 'b', 'c', 'd']);
    calls.clear();
    doc.setFeature(
      FeatureDefinition(
        id: FeatureId('a'),
        type: 'node',
        parameters: {'value': 2},
      ),
    );
    expect(calls, ['a', 'b', 'c', 'd']);
    calls.clear();
    doc.rebuild({FeatureId('b')});
    expect(calls, ['b', 'd']);
  });

  test(
    'failure blocks descendants, retains diagnostic geometry, and recovers',
    () {
      var attachedCalls = 0;
      final doc = CadDocument(
        evaluators: {
          'cube': CubeFeature.evaluate,
          'attached': (d, c) {
            attachedCalls++;
            return _attached(d, c);
          },
        },
        features: [
          _cube('a'),
          _attachedDefinition('b', 'a'),
          _attachedDefinition('c', 'b'),
          _cube('z'),
        ],
      );
      final valid = doc.evaluation;
      final failed = doc.setFeature(_cube('a', size: -1));
      expect(attachedCalls, 2);
      expect(failed.features[FeatureId('a')]!.state, FeatureState.failed);
      for (final id in ['b', 'c']) {
        expect(failed.features[FeatureId(id)]!.state, FeatureState.blocked);
        expect(failed.features[FeatureId(id)]!.outputs, isEmpty);
        expect(failed.features[FeatureId(id)]!.diagnosticOutputs, hasLength(7));
      }
      expect(failed.features[FeatureId('a')]!.outputs, isEmpty);
      expect(
        failed.features[FeatureId('a')]!.diagnosticOutputs,
        valid.features[FeatureId('a')]!.outputs,
      );
      expect(
        failed.resolve(_reference('a')).status,
        ReferenceStatus.unavailable,
      );
      expect(failed.geometry, hasLength(1));
      expect(
        failed.features[FeatureId('z')],
        same(valid.features[FeatureId('z')]),
      );
      doc.setFeature(_cube('a', size: -2));
      expect(
        doc.evaluation.features[FeatureId('a')]!.diagnosticOutputs,
        hasLength(7),
      );
      final recovered = doc.setFeature(_cube('a', size: 6));
      expect(attachedCalls, 4);
      expect(
        recovered.features.values.every((f) => f.state == FeatureState.valid),
        isTrue,
      );
      expect(
        recovered.features.values.every((f) => f.diagnosticOutputs.isEmpty),
        isTrue,
      );
      expect(recovered.geometry, hasLength(4));
    },
  );

  test('missing dependencies fail, block consumers, and rebuild on addition or removal', () {
    final calls = <String>[];
    final doc = CadDocument(
      evaluators: {
        'node': (d, c) {
          calls.add(d.id.value);
          return [];
        },
      },
      features: [
        _node('b', ['a']),
        _node('c', ['b']),
        _node('z'),
      ],
    );
    expect(calls, ['z']);
    expect(
      doc.evaluation.features[FeatureId('b')]!.issue,
      FeatureIssue.missingDependency,
    );
    expect(
      doc.evaluation.features[FeatureId('c')]!.state,
      FeatureState.blocked,
    );
    expect(
      doc.evaluation.resolve(_reference('a')).status,
      ReferenceStatus.missing,
    );
    calls.clear();
    doc.setFeature(_node('a'));
    expect(calls, ['a', 'b', 'c']);
    doc.removeFeature(FeatureId('a'));
    expect(
      doc.evaluation.features[FeatureId('b')]!.issue,
      FeatureIssue.missingDependency,
    );
    expect(
      doc.evaluation.features[FeatureId('c')]!.state,
      FeatureState.blocked,
    );
  });

  test(
    'overlapping cycles fail every cycle member, only downstream is blocked',
    () {
      final doc = CadDocument(
        evaluators: {'node': (d, c) => []},
        features: [
          _node('a', ['b', 'c']),
          _node('b', ['a']),
          _node('c', ['b']),
          _node('d', ['c']),
          _node('z'),
          _node('self', ['self']),
        ],
      );
      for (final id in ['a', 'b', 'c', 'self']) {
        expect(
          doc.evaluation.features[FeatureId(id)]!.state,
          FeatureState.failed,
        );
        expect(
          doc.evaluation.features[FeatureId(id)]!.issue,
          FeatureIssue.cycle,
        );
      }
      expect(
        doc.evaluation.features[FeatureId('d')]!.state,
        FeatureState.blocked,
      );
      expect(
        doc.evaluation.features[FeatureId('z')]!.state,
        FeatureState.valid,
      );
      doc.setFeature(_node('a'));
      for (final id in ['a', 'b', 'c', 'd']) {
        expect(
          doc.evaluation.features[FeatureId(id)]!.state,
          FeatureState.valid,
        );
      }
    },
  );

  test(
    'semantic body and face references survive dimensional and position edits',
    () {
      final doc = CadDocument(
        evaluators: {'cube': CubeFeature.evaluate},
        features: [_cube('a')],
      );
      final body = _reference('a');
      final top = _reference('a', key: 'top', kind: OutputKind.planarFace);
      final before = doc.evaluation;
      expect(before.resolve(body).output!.geometry, isA<Solid>());
      expect(_top(before, 'a'), 2);
      doc.setFeature(_cube('a', size: 10, z: 12));
      expect(doc.evaluation.resolve(body).status, ReferenceStatus.resolved);
      expect(_top(doc.evaluation, 'a'), 17);
      expect(
        (doc.evaluation.resolve(top).output!.geometry as Face).surface,
        isA<PlaneSurface>(),
      );
      expect(before.resolve(top).status, ReferenceStatus.resolved);
      expect(
        doc.evaluation.resolve(_reference('a', key: 'top')).status,
        ReferenceStatus.missing,
      );
      expect(
        doc.evaluation.resolve(_reference('a', key: 'gone')).status,
        ReferenceStatus.missing,
      );
    },
  );

  test('missing or ambiguous semantic outputs fail consumers without choosing a candidate', () {
    final geometry = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 4,
    ).build().single;
    final doc = CadDocument(
      evaluators: {
        'duplicate': (d, c) => [
          FeatureOutput(key: 'body', kind: OutputKind.body, geometry: geometry),
          FeatureOutput(key: 'body', kind: OutputKind.body, geometry: geometry),
        ],
        'copy': (d, c) => [c.input('source')],
        'node': (d, c) => [],
      },
      features: [
        FeatureDefinition(id: FeatureId('a'), type: 'duplicate'),
        FeatureDefinition(
          id: FeatureId('b'),
          type: 'copy',
          inputs: {'source': _reference('a')},
        ),
        FeatureDefinition(
          id: FeatureId('missing'),
          type: 'copy',
          inputs: {'source': _reference('a', key: 'gone')},
        ),
        _node('c', ['b']),
      ],
    );
    final resolution = doc.evaluation.resolve(_reference('a'));
    expect(resolution.status, ReferenceStatus.ambiguous);
    expect(resolution.candidateCount, 2);
    expect(resolution.output, isNull);
    expect(
      doc.evaluation.features[FeatureId('b')]!.issue,
      FeatureIssue.ambiguousOutput,
    );
    expect(
      doc.evaluation.features[FeatureId('missing')]!.issue,
      FeatureIssue.missingOutput,
    );
    expect(
      doc.evaluation.features[FeatureId('c')]!.state,
      FeatureState.blocked,
    );
  });

  test(
    'removing a named output rebuilds its consumers and restoring it recovers',
    () {
      final doc = CadDocument(
        evaluators: {
          'cube': CubeFeature.evaluate,
          'attached': _attached,
          'bodyOnly': (d, c) => CubeFeature.evaluate(
            d,
            c,
          ).where((o) => o.kind == OutputKind.body).toList(),
        },
        features: [_cube('a'), _attachedDefinition('b', 'a')],
      );
      doc.setFeature(_cube('a', type: 'bodyOnly'));
      expect(
        doc.evaluation.features[FeatureId('b')]!.issue,
        FeatureIssue.missingOutput,
      );
      expect(
        doc.evaluation.features[FeatureId('b')]!.diagnosticOutputs,
        hasLength(7),
      );
      doc.setFeature(_cube('a'));
      expect(
        doc.evaluation.features[FeatureId('b')]!.state,
        FeatureState.valid,
      );
    },
  );

  test('definitions deep-copy parameter values, inputs, and dependencies', () {
    final nested = <Object?>[
      1,
      <String, Object?>{'flag': true},
    ];
    final parameters = <String, Object?>{'nested': nested};
    final dependencies = {FeatureId('a')};
    final inputs = {'body': _reference('b')};
    final feature = FeatureDefinition(
      id: FeatureId('c'),
      type: 'node',
      parameters: parameters,
      dependencies: dependencies,
      inputs: inputs,
    );
    nested[0] = 99;
    (nested[1] as Map<String, Object?>)['flag'] = false;
    parameters.clear();
    dependencies.clear();
    inputs.clear();
    expect(feature.parameters, {
      'nested': [
        1,
        {'flag': true},
      ],
    });
    expect(feature.dependencies, {FeatureId('a'), FeatureId('b')});
    expect(feature.inputs, hasLength(1));
    expect(
      () => (feature.parameters['nested'] as List).add(3),
      throwsUnsupportedError,
    );
    expect(
      () => ((feature.parameters['nested'] as List)[1] as Map)['flag'] = false,
      throwsUnsupportedError,
    );
    expect(() => feature.dependencies.clear(), throwsUnsupportedError);
    expect(
      () => FeatureDefinition(
        id: FeatureId('x'),
        type: 'node',
        parameters: {'vector': Vector3.zero()},
      ),
      throwsArgumentError,
    );
    expect(
      () => FeatureDefinition(
        id: FeatureId('x'),
        type: 'node',
        parameters: {'bad': double.nan},
      ),
      throwsArgumentError,
    );
  });

  test('equal value definitions do not rebuild, even with different map insertion orders', () {
    var calls = 0;
    final doc = CadDocument(
      evaluators: {
        'node': (d, c) {
          calls++;
          return [];
        },
      },
      features: [
        FeatureDefinition(
          id: FeatureId('a'),
          type: 'node',
          parameters: {
            'one': [1, true],
            'two': {'x': 2},
          },
        ),
      ],
    );
    doc.setFeature(
      FeatureDefinition(
        id: FeatureId('a'),
        type: 'node',
        parameters: {
          'two': {'x': 2},
          'one': [1, true],
        },
      ),
    );
    expect(calls, 1);
    expect(doc.evaluation.rebuiltFeatures, isEmpty);
  });

  test('definition and evaluation publish atomically, duplicate IDs leave both intact', () {
    final observed = <EvaluationSnapshot>[];
    final observedParameters = <Object?>[];
    CadDocument? document;
    final doc = CadDocument(
      evaluators: {
        'cube': (d, c) {
          if (document != null) {
            observed.add(document.evaluation);
            observedParameters.add(document.features.single.parameters['size']);
          }
          return CubeFeature.evaluate(d, c);
        },
      },
      features: [_cube('a')],
    );
    document = doc;
    final before = doc.evaluation;
    final after = doc.setFeature(_cube('a', size: 8));
    expect(observed.single, same(before));
    expect(observedParameters, [4]);
    expect(after, same(doc.evaluation));
    expect(doc.features.single.parameters['size'], 8);
    expect(
      () => doc.replaceFeatures([_cube('a'), _cube('a')]),
      throwsArgumentError,
    );
    expect(doc.evaluation, same(after));
    expect(doc.features.single.parameters['size'], 8);
  });

  test('nested edits cannot publish a partial evaluation', () {
    CadDocument? document;
    var reentrantRejected = false;
    final doc = CadDocument(
      evaluators: {
        'cube': (d, c) {
          if (document != null) {
            try {
              document.removeFeature(d.id);
            } on StateError {
              reentrantRejected = true;
            }
          }
          return CubeFeature.evaluate(d, c);
        },
      },
      features: [_cube('a')],
    );
    document = doc;
    doc.setFeature(_cube('a', size: 8));
    expect(reentrantRejected, isTrue);
    expect(doc.features, hasLength(1));
    expect(doc.evaluation.features[FeatureId('a')]!.state, FeatureState.valid);
  });

  test('evaluator exceptions and unknown types fail independently', () {
    final doc = CadDocument(
      evaluators: {
        'node': (d, c) => [],
        'throws': (d, c) => throw StateError('broken'),
      },
      features: [
        FeatureDefinition(id: FeatureId('a'), type: 'throws'),
        FeatureDefinition(id: FeatureId('b'), type: 'unknown'),
        _node('c', ['a']),
        _node('z'),
      ],
    );
    expect(
      doc.evaluation.features[FeatureId('a')]!.message,
      contains('broken'),
    );
    expect(
      doc.evaluation.features[FeatureId('b')]!.issue,
      FeatureIssue.evaluationFailed,
    );
    expect(
      doc.evaluation.features[FeatureId('c')]!.state,
      FeatureState.blocked,
    );
    expect(doc.evaluation.features[FeatureId('z')]!.state, FeatureState.valid);
  });

  test('mutable producer topology, consumer inputs, and public outputs are isolated', () {
    final source = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 4,
    ).build().single;
    List<FeatureOutput>? produced;
    final doc = CadDocument(
      evaluators: {
        'source': (d, c) => produced = [
          FeatureOutput(key: 'body', kind: OutputKind.body, geometry: source),
        ],
        'mutate': (d, c) {
          final body = c.input('body').geometry as Solid;
          body.shells.single.faces.first.outerWire.edges.first.begin.vector.x =
              999;
          throw StateError('consumer failed after modifying its input');
        },
      },
      features: [
        FeatureDefinition(id: FeatureId('a'), type: 'source'),
        FeatureDefinition(
          id: FeatureId('b'),
          type: 'mutate',
          inputs: {'body': _reference('a')},
        ),
      ],
    );
    double x() =>
        (doc.evaluation.resolve(_reference('a')).output!.geometry as Solid)
            .shells
            .single
            .faces
            .first
            .outerWire
            .edges
            .first
            .begin
            .vector
            .x;
    expect(x(), -2);
    source.shells.single.faces.first.outerWire.edges.first.begin.vector.x = 888;
    produced!.clear();
    expect(x(), -2);
    final exposed =
        doc.evaluation.resolve(_reference('a')).output!.geometry as Solid;
    exposed.shells.single.faces.first.outerWire.edges.first.begin.vector.x =
        777;
    final renderGeometry = doc.evaluation.geometry.single as Solid;
    renderGeometry
            .shells
            .single
            .faces
            .first
            .outerWire
            .edges
            .first
            .begin
            .vector
            .x =
        666;
    expect(x(), -2);
    expect(doc.evaluation.features[FeatureId('b')]!.state, FeatureState.failed);
    expect(() => doc.evaluation.features.clear(), throwsUnsupportedError);
    expect(
      () => doc.evaluation.features[FeatureId('a')]!.outputs.clear(),
      throwsUnsupportedError,
    );
    expect(() => doc.features.clear(), throwsUnsupportedError);
    expect(exposed.shells.single.isClosed, isTrue);
  });

  test('evaluation context rejects undeclared reads', () {
    final doc = CadDocument(
      evaluators: {'bad': (d, c) => c.dependencyOutputs(FeatureId('other'))},
      features: [FeatureDefinition(id: FeatureId('a'), type: 'bad')],
    );
    expect(
      doc.evaluation.features[FeatureId('a')]!.message,
      contains('Undeclared dependency'),
    );
    final other = CadDocument(
      evaluators: {
        'bad': (d, c) => [c.input('undeclared')],
      },
      features: [FeatureDefinition(id: FeatureId('a'), type: 'bad')],
    );
    expect(
      other.evaluation.features[FeatureId('a')]!.message,
      contains('Undeclared input'),
    );
  });

  test(
    'topology copies retain shared curved boundaries as well as planar ones',
    () {
      final solid = Cylinder(
        frame: PlanarFrame.xy(),
        radius: 3,
        height: 8,
      ).build().single;
      final output = FeatureOutput(
        key: 'body',
        kind: OutputKind.body,
        geometry: solid,
      );
      final copy = output.geometry as Solid;
      expect(copy.shells.single.isClosed, isTrue);
      expect(copy, isNot(same(solid)));
      copy.shells.single.faces.first.outerWire.edges.first.begin.vector.x = 123;
      expect((output.geometry as Solid).shells.single.isClosed, isTrue);
    },
  );

  test('output kinds reject incompatible topology', () {
    final body = Cube(
      centerPosition: Vertex(Vector3.zero()),
      size: 4,
    ).build().single;
    expect(
      () => FeatureOutput(
        key: 'face',
        kind: OutputKind.planarFace,
        geometry: body,
      ),
      throwsArgumentError,
    );
    expect(
      () => FeatureOutput(
        key: 'body',
        kind: OutputKind.body,
        geometry: body.shells.single.faces.first,
      ),
      throwsArgumentError,
    );
  });
}

FeatureDefinition _cube(
  String id, {
  double size = 4,
  double z = 0,
  String type = 'cube',
}) => FeatureDefinition(
  id: FeatureId(id),
  type: type,
  parameters: {'size': size, 'x': 0, 'y': 0, 'z': z},
);
FeatureDefinition _node(String id, [List<String> dependencies = const []]) =>
    FeatureDefinition(
      id: FeatureId(id),
      type: 'node',
      dependencies: dependencies.map(FeatureId.new).toSet(),
    );
OutputReference _reference(
  String id, {
  String key = 'body',
  OutputKind kind = OutputKind.body,
}) => OutputReference(featureId: FeatureId(id), key: key, kind: kind);
FeatureDefinition _attachedDefinition(String id, String parent) =>
    FeatureDefinition(
      id: FeatureId(id),
      type: 'attached',
      inputs: {
        'support': _reference(parent, key: 'top', kind: OutputKind.planarFace),
      },
    );

// Small test feature: rebuild a half-sized Cube above a semantic support face.
List<FeatureOutput> _attached(
  FeatureDefinition definition,
  FeatureEvaluationContext context,
) {
  final face = context.input('support').geometry as Face;
  final plane = face.surface as PlaneSurface;
  final size =
      face.outerWire.edges.first
          .evaluate(1)
          .distanceTo(face.outerWire.edges.first.evaluate(0)) /
      2;
  return CubeFeature.evaluate(
    FeatureDefinition(
      id: definition.id,
      type: 'cube',
      parameters: {
        'size': size,
        'x': plane.origin.x,
        'y': plane.origin.y,
        'z': plane.origin.z + size / 2,
      },
    ),
    context,
  );
}

double _top(EvaluationSnapshot snapshot, String id) =>
    ((snapshot
                        .resolve(
                          _reference(
                            id,
                            key: 'top',
                            kind: OutputKind.planarFace,
                          ),
                        )
                        .output!
                        .geometry
                    as Face)
                .surface
            as PlaneSurface)
        .origin
        .z;
