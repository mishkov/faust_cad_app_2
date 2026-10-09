import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/document_edit.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DocumentController controller;
  final a = FeatureId('a');
  final b = FeatureId('b');

  setUp(() {
    controller = DocumentController(
      evaluators: {
        'cube': CubeFeature.evaluate,
        'copy': (definition, context) => [context.input('source')],
      },
      features: [_cube('a')],
    );
  });
  tearDown(() => controller.dispose());

  test('starts with no history and empty undo/redo are no-ops', () {
    final evaluation = controller.evaluation;
    expect(controller.canUndo, isFalse);
    expect(controller.canRedo, isFalse);
    expect(controller.undoLabel, isNull);
    expect(controller.redoLabel, isNull);
    expect(controller.undo(), isFalse);
    expect(controller.redo(), isFalse);
    expect(controller.evaluation, same(evaluation));
  });

  test('add, parameter change, and remove restore IDs, order and geometry', () {
    controller.addFeature(_cube('b', size: 6));
    expect(controller.undoCount, 1);
    expect(controller.undoLabel, 'Add feature');
    controller.updateParameters(a, {'size': 8});
    expect(_top(controller, a), 4);
    controller.removeFeature(b);
    expect(controller.features.map((f) => f.id), [a]);
    expect(controller.undo(), isTrue);
    expect(controller.features.map((f) => f.id), [a, b]);
    expect(_top(controller, b), 3);
    controller.undo();
    expect(_top(controller, a), 2);
    controller.undo();
    expect(controller.features.map((f) => f.id), [a]);
    expect(controller.redoLabel, 'Add feature');
    controller.redo();
    controller.redo();
    controller.redo();
    expect(controller.features.map((f) => f.id), [a]);
    expect(_top(controller, a), 4);
  });

  test('grouped edits evaluate once and undo and redo as one command', () {
    final initial = controller.features;
    final revision = controller.evaluation.revision;
    controller.edit('Make assembly', (draft) {
      draft.updateParameters(a, {'size': 10});
      draft.addFeature(_copy('b', 'a'));
      draft.addFeature(_copy('c', 'b'));
    });
    expect(controller.evaluation.revision, revision + 1);
    expect(controller.undoCount, 1);
    expect(controller.undoLabel, 'Make assembly');
    expect(controller.evaluation.geometry, hasLength(3));
    final assembly = controller.features;
    controller.undo();
    expect(controller.features, initial);
    expect(controller.evaluation.geometry, hasLength(1));
    controller.redo();
    expect(controller.features, assembly);
    expect(_top(controller, a), 5);
    expect(controller.evaluation.geometry, hasLength(3));
  });

  test(
    'interactive previews coalesce into one entry with the transaction label',
    () {
      controller.beginTransaction('Drag cube');
      for (var z = 1; z <= 25; z++) {
        controller.updateParameters(a, {'z': z});
        expect(_top(controller, a), z + 2);
        expect(controller.undoCount, 0);
      }
      expect(controller.hasActiveTransaction, isTrue);
      expect(controller.canUndo, isFalse);
      expect(controller.commitTransaction(), isTrue);
      expect(controller.undoCount, 1);
      expect(controller.undoLabel, 'Drag cube');
      controller.undo();
      expect(_top(controller, a), 2);
      controller.redo();
      expect(_top(controller, a), 27);
    },
  );

  test(
    'cancellation restores a mixed edit group and retains both history stacks',
    () {
      controller.addFeature(_cube('b'));
      controller.updateParameters(a, {'size': 8});
      controller.undo();
      final before = controller.features;
      controller.beginTransaction('Cancelled drag and delete');
      controller.updateParameters(a, {'size': 12});
      controller.removeFeature(b);
      controller.addFeature(_cube('c'));
      controller.cancelTransaction();
      expect(controller.hasActiveTransaction, isFalse);
      expect(controller.features, before);
      expect(_top(controller, a), 2);
      expect(controller.undoCount, 1);
      expect(controller.redoCount, 1);
      controller.redo();
      expect(_top(controller, a), 4);
    },
  );

  test('empty and net-zero transactions preserve redo without new entries', () {
    controller.updateParameters(a, {'size': 8});
    controller.undo();
    final evaluation = controller.evaluation;
    controller.beginTransaction('Empty');
    expect(controller.commitTransaction(), isFalse);
    expect(controller.evaluation, same(evaluation));
    controller.beginTransaction('Move away and back');
    controller.updateParameters(a, {'size': 12});
    controller.updateParameters(a, {'size': 4});
    expect(controller.commitTransaction(), isFalse);
    expect(controller.undoCount, 0);
    expect(controller.redoCount, 1);
    controller.redo();
    expect(_top(controller, a), 4);
  });

  test('deletion and restoration rebuild dependent semantic references', () {
    controller.edit('Assembly', (draft) {
      draft.addFeature(_copy('b', 'a'));
      draft.addFeature(_copy('c', 'b'));
    });
    final definitions = controller.features;
    controller.removeFeature(a);
    expect(
      controller.evaluation.features[b]!.issue,
      FeatureIssue.missingDependency,
    );
    expect(
      controller.evaluation.features[FeatureId('c')]!.state,
      FeatureState.blocked,
    );
    expect(controller.evaluation.geometry, isEmpty);
    controller.undo();
    expect(controller.features, definitions);
    expect(controller.features[1].inputs['source'], _body('a'));
    expect(controller.features[1].dependencies, {a});
    expect(
      controller.evaluation.resolve(_body('b')).status,
      ReferenceStatus.resolved,
    );
    expect(controller.evaluation.geometry, hasLength(3));
    controller.redo();
    expect(controller.evaluation.features[b]!.state, FeatureState.failed);
    controller.undo();
    controller.updateParameters(a, {'size': 10});
    expect(controller.features[1], definitions[1]);
    expect(_bodyX(controller, b), -5);
  });

  test(
    'valid value edits with geometry failures are committed and undoable',
    () {
      controller.addFeature(_copy('b', 'a'));
      controller.updateParameters(a, {'size': -1}, label: 'Invalid geometry');
      expect(controller.features.first.parameters['size'], -1);
      expect(controller.undoLabel, 'Invalid geometry');
      expect(controller.evaluation.features[a]!.state, FeatureState.failed);
      expect(
        controller.evaluation.features[a]!.issue,
        FeatureIssue.evaluationFailed,
      );
      expect(
        controller.evaluation.features[a]!.diagnosticOutputs,
        hasLength(7),
      );
      expect(controller.evaluation.features[b]!.state, FeatureState.blocked);
      expect(controller.evaluation.geometry, isEmpty);
      controller.undo();
      expect(_top(controller, a), 2);
      expect(controller.evaluation.features[b]!.state, FeatureState.valid);
      expect(controller.evaluation.features[a]!.diagnosticOutputs, isEmpty);
      controller.redo();
      expect(controller.evaluation.features[a]!.state, FeatureState.failed);
      expect(controller.evaluation.features[b]!.state, FeatureState.blocked);
      controller.undo();
      expect(controller.evaluation.geometry, hasLength(2));
    },
  );

  test('failed transaction previews may be committed or cancelled', () {
    controller.addFeature(_copy('b', 'a'));
    controller.beginTransaction('Drag past valid geometry');
    controller.updateParameters(a, {'size': -2});
    expect(controller.evaluation.features[b]!.state, FeatureState.blocked);
    controller.cancelTransaction();
    expect(_top(controller, a), 2);
    expect(controller.undoCount, 1);
    controller.beginTransaction('Commit failed geometry');
    controller.updateParameters(a, {'size': -3});
    controller.commitTransaction();
    expect(controller.undoCount, 2);
    controller.undo();
    expect(controller.evaluation.features[b]!.state, FeatureState.valid);
    controller.redo();
    expect(controller.evaluation.features[b]!.state, FeatureState.blocked);
  });

  test('new committed edits invalidate redo; previews wait until commit', () {
    controller.updateParameters(a, {'size': 8});
    controller.undo();
    controller.beginTransaction('New drag');
    controller.updateParameters(a, {'z': 10});
    expect(controller.redoCount, 1);
    expect(controller.canRedo, isFalse);
    controller.commitTransaction();
    expect(controller.redoCount, 0);
    expect(controller.redo(), isFalse);
    controller.undo();
    controller.addFeature(_cube('b'));
    expect(controller.redoCount, 0);
  });

  test('equal commands preserve redo and do not evaluate or notify', () {
    controller.updateParameters(a, {'size': 8});
    controller.undo();
    final evaluation = controller.evaluation;
    var notifications = 0;
    controller.addListener(() => notifications++);
    expect(controller.setFeature(_cube('a')), isFalse);
    expect(controller.updateParameters(a, {'size': 4}), isFalse);
    expect(controller.edit('No-op', (_) {}), isFalse);
    expect(controller.evaluation, same(evaluation));
    expect(controller.redoCount, 1);
    expect(notifications, 0);
  });

  test('rejected commands never publish staged changes or modify history', () {
    controller.updateParameters(a, {'size': 8});
    controller.undo();
    final before = controller.features;
    final evaluation = controller.evaluation;
    var notifications = 0;
    controller.addListener(() => notifications++);
    final commands = <void Function()>[
      () => controller.edit('Rejected group', (draft) {
        draft.updateParameters(a, {'size': 10});
        draft.addFeature(_cube('b'));
        throw StateError('Rejected before commit');
      }),
      () => controller.edit('Duplicate', (draft) {
        draft.removeFeature(a);
        draft.replaceFeatures([_cube('b'), _cube('b')]);
      }),
      () => controller.addFeature(_cube('a')),
      () => controller.removeFeature(b),
      () => controller.updateParameters(b, {'size': 1}),
      () => controller.updateParameters(a, {'size': double.nan}),
      () => controller.updateParameters(a, {'size': Object()}),
    ];
    for (final command in commands) {
      expect(command, throwsA(anything));
      expect(controller.features, before);
      expect(controller.evaluation, same(evaluation));
      expect(controller.undoCount, 0);
      expect(controller.redoCount, 1);
    }
    expect(notifications, 0);
  });

  test(
    'rejected command during transaction retains the last accepted preview',
    () {
      controller.beginTransaction('Drag');
      controller.updateParameters(a, {'z': 5});
      final evaluation = controller.evaluation;
      expect(
        () => controller.edit('Rejected', (draft) {
          draft.updateParameters(a, {'z': 7});
          draft.removeFeature(b);
        }),
        throwsArgumentError,
      );
      expect(controller.evaluation, same(evaluation));
      expect(controller.hasActiveTransaction, isTrue);
      controller.commitTransaction();
      controller.undo();
      expect(_top(controller, a), 2);
      controller.redo();
      expect(_top(controller, a), 7);
    },
  );

  test('transaction lifecycle rejects nesting and history actions without side effects', () {
    expect(controller.commitTransaction, throwsStateError);
    expect(controller.cancelTransaction, throwsStateError);
    controller.beginTransaction('Drag');
    controller.updateParameters(a, {'z': 1});
    final evaluation = controller.evaluation;
    expect(() => controller.beginTransaction('Nested'), throwsStateError);
    expect(controller.undo, throwsStateError);
    expect(controller.redo, throwsStateError);
    expect(controller.evaluation, same(evaluation));
    controller.cancelTransaction();
    expect(controller.undoCount, 0);
  });

  test(
    'replacement restores types, parameters, ordering, and dependencies',
    () {
      controller.addFeature(_copy('b', 'a'));
      final before = controller.features;
      controller.replaceFeatures([
        _cube('b', size: 10),
        FeatureDefinition(id: a, type: 'copy', inputs: {'source': _body('b')}),
      ]);
      final after = controller.features;
      controller.undo();
      expect(controller.features, before);
      controller.redo();
      expect(controller.features, after);
      expect(controller.features.map((f) => f.id), [b, a]);
      expect(controller.features.last.dependencies, {b});
      expect(_bodyX(controller, a), -5);
    },
  );

  test('saved state is isolated from nested values, collections, drafts and later edits', () {
    final nested = <Object?>[
      1,
      <String, Object?>{'flag': true},
    ];
    final values = <String, Object?>{'metadata': nested};
    DocumentEdit? retained;
    controller.edit('Metadata', (draft) {
      retained = draft;
      draft.updateParameters(a, values);
    });
    final saved = controller.features;
    nested[0] = 99;
    (nested[1] as Map<String, Object?>)['flag'] = false;
    values.clear();
    retained!.removeFeature(a);
    expect(controller.features, saved);
    expect(() => controller.features.clear(), throwsUnsupportedError);
    expect(
      () => (saved.single.parameters['metadata'] as List).clear(),
      throwsUnsupportedError,
    );
    controller.updateParameters(a, {
      'metadata': [7],
      'size': 10,
    });
    controller.undo();
    expect(controller.features.single.parameters['metadata'], [
      1,
      {'flag': true},
    ]);
    expect(_top(controller, a), 2);
    controller.undo();
    expect(
      controller.features.single.parameters.containsKey('metadata'),
      isFalse,
    );
    controller.redo();
    expect(controller.features, saved);
    controller.redo();
    expect(controller.features.single.parameters['metadata'], [7]);
  });

  test('caller-owned feature lists, input maps and dependency sets cannot corrupt history', () {
    final inputs = {'source': _body('a')};
    final dependencies = {a};
    final definitions = [
      _cube('a'),
      FeatureDefinition(
        id: b,
        type: 'copy',
        inputs: inputs,
        dependencies: dependencies,
      ),
    ];
    controller.replaceFeatures(definitions);
    inputs.clear();
    dependencies.clear();
    definitions.clear();
    controller.removeFeature(b);
    controller.undo();
    expect(controller.features.last.inputs, {'source': _body('a')});
    expect(controller.features.last.dependencies, {a});
    expect(controller.evaluation.features[b]!.state, FeatureState.valid);
  });

  test('undo and redo rebuild geometry rather than retaining mutable derived outputs', () {
    controller.updateParameters(a, {'size': 8});
    final exposed = controller.evaluation.geometry.single as Solid;
    exposed.shells.single.faces.first.outerWire.edges.first.begin.vector.x =
        999;
    controller.undo();
    expect(_bodyX(controller, a), -2);
    controller.redo();
    expect(_bodyX(controller, a), -4);
  });

  test('external rebuilds are not edits and undo/redo use current evaluator inputs', () {
    var offset = 0;
    final calls = <int>[];
    final external = DocumentController(
      evaluators: {
        'external': (d, c) {
          calls.add(offset);
          return CubeFeature.evaluate(
            FeatureDefinition(
              id: d.id,
              type: 'cube',
              parameters: {...d.parameters, 'z': offset},
            ),
            c,
          );
        },
      },
      features: [_cube('a', type: 'external')],
    );
    addTearDown(external.dispose);
    external.updateParameters(a, {'size': 8});
    external.undo();
    offset = 10;
    external.rebuild({a});
    expect(external.undoCount, 0);
    expect(external.redoCount, 1);
    expect(_top(external, a), 12);
    external.redo();
    expect(_top(external, a), 14);
    external.undo();
    expect(_top(external, a), 12);
    expect(calls, [0, 0, 0, 10, 10, 10]);
  });

  test('undo after an explicit rebuild failure recovers and redo remains available', () {
    var maximumSize = 10;
    final external = DocumentController(
      evaluators: {
        'copy': (definition, context) => [context.input('source')],
        'cube': (definition, context) {
          if ((definition.parameters['size'] as num) > maximumSize) {
            throw StateError('Size exceeds current evaluator limit');
          }
          return CubeFeature.evaluate(definition, context);
        },
      },
      features: [_cube('a'), _copy('b', 'a')],
    );
    addTearDown(external.dispose);
    external.updateParameters(a, {'size': 8});
    maximumSize = 6;
    external.rebuild({a});
    expect(external.features.first.parameters['size'], 8);
    expect(external.evaluation.features[a]!.state, FeatureState.failed);
    expect(external.evaluation.features[b]!.state, FeatureState.blocked);
    expect(external.undoCount, 1);
    external.undo();
    expect(_top(external, a), 2);
    expect(external.evaluation.features[b]!.state, FeatureState.valid);
    expect(external.canRedo, isTrue);
    external.redo();
    expect(external.evaluation.features[a]!.state, FeatureState.failed);
    expect(external.evaluation.features[b]!.state, FeatureState.blocked);
  });

  test(
    'notifications observe complete evaluation and history publications',
    () {
      final observed = <(double, int, int, bool)>[];
      controller.addListener(
        () => observed.add((
          _top(controller, a),
          controller.undoCount,
          controller.redoCount,
          controller.hasActiveTransaction,
        )),
      );
      controller.updateParameters(a, {'size': 8});
      controller.undo();
      controller.redo();
      controller.beginTransaction('Drag');
      controller.updateParameters(a, {'z': 5});
      controller.commitTransaction();
      expect(observed, [
        (4, 1, 0, false),
        (2, 0, 1, false),
        (4, 1, 0, false),
        (4, 1, 0, true),
        (9, 1, 0, true),
        (9, 2, 0, false),
      ]);
    },
  );

  test('nested commands from drafts, evaluators or listeners cannot change saved history', () {
    expect(
      () => controller.edit('Outer', (draft) {
        draft.updateParameters(a, {'size': 6});
        controller.removeFeature(a);
      }),
      throwsStateError,
    );
    expect(controller.undoCount, 0);
    var rejected = 0;
    controller.addListener(() {
      try {
        controller.undo();
      } on StateError {
        rejected++;
      }
    });
    controller.updateParameters(a, {'size': 8});
    expect(rejected, 1);
    expect(controller.undoCount, 1);

    DocumentController? evaluated;
    final other = DocumentController(
      evaluators: {
        'cube': (d, c) {
          if (evaluated != null) {
            try {
              evaluated.removeFeature(a);
            } on StateError {
              rejected++;
            }
          }
          return CubeFeature.evaluate(d, c);
        },
      },
      features: [_cube('a')],
    );
    evaluated = other;
    addTearDown(other.dispose);
    other.updateParameters(a, {'size': 8});
    other.undo();
    other.redo();
    expect(rejected, 4);
    expect(other.undoCount, 1);
    expect(other.features, hasLength(1));
    expect(_top(other, a), 4);
  });
}

FeatureDefinition _cube(String id, {double size = 4, String type = 'cube'}) =>
    FeatureDefinition(
      id: FeatureId(id),
      type: type,
      parameters: {'size': size, 'x': 0, 'y': 0, 'z': 0},
    );

FeatureDefinition _copy(String id, String parent) => FeatureDefinition(
  id: FeatureId(id),
  type: 'copy',
  inputs: {'source': _body(parent)},
);

OutputReference _body(String id) => OutputReference(
  featureId: FeatureId(id),
  key: 'body',
  kind: OutputKind.body,
);

double _top(DocumentController controller, FeatureId id) =>
    ((controller.evaluation
                        .resolve(
                          OutputReference(
                            featureId: id,
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

double _bodyX(DocumentController controller, FeatureId id) =>
    (controller.evaluation.resolve(_body(id.value)).output!.geometry as Solid)
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
