import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentController emptyDocument() => DocumentController(
  evaluators: {
    CubeFeature.type: CubeFeature.evaluate,
    SketchFeature.type: SketchFeature.evaluate,
    ExtrudeFeature.type: ExtrudeFeature.evaluate,
  },
);

Map<String, Object?> washerSketch() => {
  'featureId': 'washer',
  'plane': 'xy',
  'points': [
    {'id': 'center', 'x': 0, 'y': 0},
  ],
  'segments': [],
  'circles': [
    {'id': 'rim', 'center': 'center', 'radius': 10},
    {'id': 'bore', 'center': 'center', 'radius': 2.5},
  ],
};

Map<String, Object?> data(Map<String, Object?> result) =>
    result['structuredContent'] as Map<String, Object?>;

void main() {
  late DocumentController document;
  late AutomationController ai;
  late String session;
  var request = 0;
  Future<Map<String, Object?>> edit(String name, Map<String, Object?> args) =>
      ai.call('client', name, {
        'sessionId': session,
        'requestId': 'op-${++request}',
        'expectedRevision': document.evaluation.revision,
        ...args,
      });

  setUp(() async {
    document = emptyDocument();
    ai = AutomationController(document);
    session =
        data(await ai.call('client', 'cad_begin', {}))['sessionId'] as String;
  });
  tearDown(() {
    ai.dispose();
    document.dispose();
  });

  test(
    'shared command layer locks human edits, finish restores editing',
    () async {
      expect(document.isEditLocked, isTrue);
      expect(() => document.undo(), throwsStateError);
      expect(() => document.allocateFeatureId('human'), throwsStateError);
      expect((await ai.call('other', 'cad_begin', {}))['isError'], isTrue);
      await ai.call('client', 'cad_finish', {'sessionId': session});
      expect(document.isEditLocked, isFalse);
      expect(document.undo(), isFalse);
    },
  );

  test('washer sketch and holed extrusion are two undo steps', () async {
    expect((await edit('cad_set_sketch', washerSketch()))['isError'], isNull);
    final profiles = data(
      await ai.call('client', 'cad_get_profiles', {'sketchId': 'washer'}),
    );
    final annulus = (profiles['regions'] as List).cast<Map>().singleWhere(
      (r) => r['holeCount'] == 1,
    );
    final result = await edit('cad_extrude', {
      'featureId': 'body',
      'sketchId': 'washer',
      'regionIds': [annulus['id']],
      'distance': 5,
    });
    expect(result['isError'], isNull, reason: result.toString());
    expect(document.undoCount, 2);
    expect(document.evaluation.geometry, hasLength(1));
    expect(document.features.last.parameters['distance'], 5);
    await edit('cad_undo', {});
    expect(document.features, hasLength(1));
    expect(document.evaluation.geometry, isEmpty);
    await edit('cad_redo', {});
    expect(document.evaluation.geometry, hasLength(1));
  });

  test(
    'lost response retry returns receipt; ID reuse cannot create a new edit',
    () async {
      final args = {
        'sessionId': session,
        'requestId': 'same',
        'expectedRevision': document.evaluation.revision,
        ...washerSketch(),
      };
      final first = await ai.call('client', 'cad_set_sketch', args);
      final second = await ai.call(
        'client',
        'cad_set_sketch',
        Map.fromEntries(args.entries.toList().reversed),
      );
      expect(second, first);
      expect(document.undoCount, 1);
      expect(
        (await ai.call('client', 'cad_set_sketch', {
          ...args,
          'name': 'different',
        }))['isError'],
        isTrue,
      );
      expect(document.undoCount, 1);
    },
  );

  test('failed upstream edit preserves geometry, revision and redo', () async {
    await edit('cad_set_sketch', washerSketch());
    final profiles = data(
      await ai.call('client', 'cad_get_profiles', {'sketchId': 'washer'}),
    );
    final annulus = (profiles['regions'] as List).cast<Map>().singleWhere(
      (r) => r['holeCount'] == 1,
    );
    await edit('cad_extrude', {
      'featureId': 'body',
      'sketchId': 'washer',
      'regionIds': [annulus['id']],
      'distance': 5,
    });
    final revision = document.evaluation.revision;
    final count = document.undoCount;
    final failed = await edit('cad_delete_feature', {'featureId': 'washer'});
    expect(failed['isError'], isTrue);
    expect(document.evaluation.revision, revision);
    expect(document.undoCount, count);
    expect(document.evaluation.geometry, hasLength(1));
    await edit('cad_undo', {});
    final invalid = await edit('cad_extrude', {
      'featureId': 'bad',
      'sketchId': 'missing',
      'regionIds': ['x'],
      'distance': 5,
    });
    expect(invalid['isError'], isTrue);
    expect(document.redoCount, 1);
  });

  test(
    'Stop AI discards in-flight draft and rejects stale authority',
    () async {
      final pending = edit('cad_set_sketch', washerSketch());
      ai.stop();
      final result = await pending;
      expect(result['isError'], isTrue);
      expect(document.features, isEmpty);
      expect(document.undoCount, 0);
      expect(document.isEditLocked, isFalse);
      expect((await ai.call('client', 'cad_begin', {}))['isError'], isTrue);
      ai.enable();
      final next = await ai.call('client', 'cad_begin', {});
      expect(next['isError'], isNull);
      expect((await edit('cad_set_sketch', washerSketch()))['isError'], isTrue);
    },
  );

  test('Stop AI also discards in-flight undo without moving history', () async {
    await edit('cad_set_sketch', washerSketch());
    final undo = edit('cad_undo', {});
    ai.stop();
    expect((await undo)['isError'], isTrue);
    expect(document.features, hasLength(1));
    expect(document.undoCount, 1);
    expect(document.redoCount, 0);
  });

  test('disconnect and idle lease release locks', () async {
    ai.disconnect('other');
    expect(document.isEditLocked, isTrue);
    ai.disconnect('client');
    expect(document.isEditLocked, isFalse);
    ai.dispose();
    ai = AutomationController(
      document,
      leaseDuration: const Duration(milliseconds: 10),
    );
    await ai.call('client', 'cad_begin', {});
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(document.isEditLocked, isFalse);
  });

  test(
    'stale revisions, unknown fields and invalid dimensions are rejected',
    () async {
      expect(
        (await edit('cad_set_sketch', {
          ...washerSketch(),
          'expectedRevision': -1,
        }))['isError'],
        isTrue,
      );
      expect(
        (await edit('cad_set_sketch', {
          ...washerSketch(),
          'unexpected': true,
        }))['isError'],
        isTrue,
      );
      expect(
        (await edit('cad_set_sketch', {
          ...washerSketch(),
          'points': [
            {'id': 'center', 'x': double.nan, 'y': 0},
          ],
        }))['isError'],
        isTrue,
      );
      expect(document.undoCount, 0);
    },
  );
}
