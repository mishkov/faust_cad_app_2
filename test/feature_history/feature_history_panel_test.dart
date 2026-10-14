import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_failure.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:faust_cad_app_2/feature_history/feature_history_panel.dart';
import 'package:faust_cad_app_2/feature_history/feature_name_dialog.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:faust_cad_app_2/extrusion_editor/extrusion_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../support/feature_history_fixtures.dart';
import '../support/linked_extrusion_fixtures.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find.descendant(
      of: find.byKey(const Key('feature-history-list')),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: scrollable,
      maxScrolls: 100,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder item(FeatureId id) => find.byKey(Key('history-${id.value}'));

void main() {
  testWidgets(
    'authored rows, selection and camera preserve model undo; rename and delete retain dependents',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = historyDocument();
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
      final initial = doc.features;
      final evaluation = doc.evaluation;
      expect(find.text('Feature history'), findsOneWidget);
      expect(find.text('1. Base profile'), findsOneWidget);
      expect(find.text('2. Main extrusion'), findsOneWidget);
      expect(
        find.descendant(
          of: item(linkedExtrusionId),
          matching: find.text('Dependencies: Base profile'),
        ),
        findsOneWidget,
      );
      final panel = tester.widget<FeatureHistoryPanel>(
        find.byType(FeatureHistoryPanel),
      );
      expect(panel.document.features, initial);
      expect(
        doc.evaluation.evaluationOrder,
        isNot(initial.map((f) => f.id).toList()),
      );
      await tapVisible(tester, find.text('2. Main extrusion'));
      final selectedScene = tester.widget<CadScene>(find.byType(CadScene));
      expect(selectedScene.selectedReference!.featureId, linkedExtrusionId);
      final position = tester.getCenter(find.byType(CadScene));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          scale: 1.2,
          panDelta: const Offset(10, 15),
          pan: const Offset(10, 15),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: position),
      );
      await tester.pump();
      expect(
        tester.widget<CadScene>(find.byType(CadScene)).cameraConfig,
        isNot(selectedScene.cameraConfig),
      );
      expect(doc.undoCount, 0);
      expect(doc.features, initial);
      expect(doc.evaluation, same(evaluation));
      await tapVisible(
        tester,
        find.byKey(Key('rename-${linkedExtrusionId.value}')),
      );
      await tester.enterText(find.byKey(const Key('feature-name')), '  ');
      await tester.tap(find.byKey(const Key('confirm-rename')));
      await tester.pump();
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(doc.undoCount, 0);
      await tester.enterText(find.byKey(const Key('feature-name')), 'Boss');
      await tester.tap(find.byKey(const Key('confirm-rename')));
      await tester.pumpAndSettle();
      expect(find.text('2. Boss'), findsOneWidget);
      expect(doc.undoCount, 1);
      expect(doc.features[1].id, initial[1].id);
      expect(doc.features[1].inputs, initial[1].inputs);
      expect(doc.features[1].parameters, initial[1].parameters);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.text('2. Main extrusion'), findsOneWidget);
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(find.text('2. Boss'), findsOneWidget);
      await tapVisible(tester, find.text('1. Base profile'));
      await tapVisible(
        tester,
        find.byKey(Key('delete-${linkedSketchId.value}')),
      );
      expect(find.text('Affected dependents (5):'), findsOneWidget);
      for (final name in [
        'Boss',
        'Reverse branch',
        'Cap profile',
        'Cap extrusion',
        'Top profile',
      ]) {
        expect(find.textContaining('• $name ('), findsOneWidget);
      }
      expect(
        find.textContaining('Only this feature will be deleted.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(doc.features, hasLength(7));
      expect(doc.undoCount, 1);
      await tapVisible(
        tester,
        find.byKey(Key('delete-${linkedSketchId.value}')),
      );
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await tester.pumpAndSettle();
      expect(doc.features, hasLength(6));
      expect(find.byKey(Key('history-${linkedSketchId.value}')), findsNothing);
      expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
      expect(
        tester
            .widget<CadScene>(find.byType(CadScene))
            .evaluatedGeometry!
            .bodies
            .values
            .single
            .featureId,
        independentId,
      );
      expect(
        find.descendant(
          of: item(linkedExtrusionId),
          matching: find.textContaining('failed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: item(linkedExtrusionId),
          matching: find.textContaining('(missing)'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(doc.features, hasLength(7));
      expect(doc.features.first, initial.first);
      expect(doc.evaluation.materializeGeometry().bodies, hasLength(4));
      await tester.tap(find.byTooltip('Redo'));
      await tester.pumpAndSettle();
      expect(doc.features, hasLength(6));
      expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reopen early sketch and edit extrusion rebuild the complete viewport; undo redo refresh it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = historyDocument();
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
      final before = doc.features;
      final independent = doc.evaluation.features[independentId];
      final camera = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      await tapVisible(tester, find.byKey(Key('open-${linkedSketchId.value}')));
      final editor = tester
          .widget<SketchWorkspace>(find.byType(SketchWorkspace))
          .editor;
      expect(doc.undoCount, 0);
      editor.beginDrag(SketchEntityId('p0-2'), Vector2(4, 3));
      editor.updateDrag(Vector2(8, 3));
      editor.endDrag();
      await tester.pump();
      expect(doc.undoCount, 1);
      expect(
        doc.evaluation.rebuiltFeatures,
        containsAll([
          linkedSketchId,
          linkedExtrusionId,
          branchExtrusionId,
          capSketchId,
          laterExtrusionId,
          laterSketchId,
        ]),
      );
      expect(doc.evaluation.features[independentId], same(independent));
      await tester.tap(find.byKey(const Key('finish-sketch')));
      await tester.pumpAndSettle();
      final scene = tester.widget<CadScene>(find.byType(CadScene));
      expect(scene.cameraConfig, camera);
      expect(scene.geometryRevision, doc.evaluation.revision);
      expect(scene.evaluatedGeometry!.bodies, hasLength(4));
      await tapVisible(
        tester,
        find.byKey(Key('edit-${linkedExtrusionId.value}')),
      );
      expect(find.byType(ExtrusionWorkspace), findsOneWidget);
      await tester.enterText(find.byKey(const Key('extrusion-distance')), '8');
      await tester.tap(find.byKey(const Key('extrusion-reverse')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-extrusion')));
      await tester.pumpAndSettle();
      expect(doc.undoCount, 2);
      expect(doc.evaluation.features[capSketchId]!.support!.frame.origin.z, -8);
      expect(
        doc.evaluation.features[laterSketchId]!.support!.frame.origin.z,
        -10,
      );
      expect(doc.features[1].name, 'Main extrusion');
      final edited = doc.features;
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Undo'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<CadScene>(find.byType(CadScene)).geometryRevision,
          doc.evaluation.revision,
        );
      }
      expect(doc.features, before);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Redo'));
        await tester.pumpAndSettle();
      }
      expect(doc.features, edited);
      editor.open(linkedSketchId);
      editor.selectEntity(SketchEntityId('line0-0'));
      editor.deleteSelection();
      editor.close();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CadScene>(find.byType(CadScene))
            .evaluatedGeometry!
            .bodies
            .values
            .single
            .featureId,
        independentId,
      );
      await tapVisible(tester, find.text('2. Main extrusion'));
      expect(
        find.descendant(
          of: item(linkedExtrusionId),
          matching: find.textContaining(
            'Selected profile references are missing.',
          ),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('4. Cap profile'));
      expect(
        find.descendant(
          of: item(capSketchId),
          matching: find.textContaining('brokenAttachment'),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('5. Cap extrusion'));
      final blocked = find.descendant(
        of: item(laterExtrusionId),
        matching: find.textContaining('blocked'),
      );
      await tester.ensureVisible(blocked);
      await tester.pumpAndSettle();
      expect(blocked, findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(doc.features, edited);
      expect(
        tester
            .widget<CadScene>(find.byType(CadScene))
            .evaluatedGeometry!
            .bodies,
        hasLength(4),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'published ambiguous profile diagnostic appears at its affected extrusion',
    (tester) async {
      final source = historyDocument();
      final doc = DocumentController(
        features: source.features,
        evaluators: {
          ...historyEvaluators,
          ExtrudeFeature.type: (definition, context) {
            if (definition.id == linkedExtrusionId) {
              throw FeatureEvaluationFailure(
                message: 'Selected profile references are ambiguous.',
                diagnostics: {
                  'extrusionCode': 'brokenProfiles',
                  'profileStatus': 'ambiguous',
                },
              );
            }
            return ExtrudeFeature.evaluate(definition, context);
          },
        },
      );
      source.dispose();
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
      await tapVisible(tester, find.text('2. Main extrusion'));
      expect(
        find.descendant(
          of: item(linkedExtrusionId),
          matching: find.textContaining(
            'Selected profile references are ambiguous.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        doc.evaluation.features[branchExtrusionId]!.state,
        FeatureState.valid,
      );
      expect(doc.evaluation.features[independentId]!.state, FeatureState.valid);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rename submits the current field value for platform text edits', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) =>
                    const FeatureNameDialog(initialName: 'Original'),
              );
            },
            child: const Text('Open rename'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open rename'));
    await tester.pumpAndSettle();
    // Platform/autofill/programmatic updates may update the controller without
    // invoking onChanged. Submit the actual field value in every case.
    tester
            .widget<TextFormField>(find.byKey(const Key('feature-name')))
            .controller!
            .text =
        'Current value';
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-rename')));
    await tester.pumpAndSettle();
    expect(result, 'Current value');
  });

  testWidgets('empty history and narrow panel remain usable', (tester) async {
    final doc = DocumentController(evaluators: historyEvaluators);
    addTearDown(doc.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 220,
          child: FeatureHistoryPanel(
            document: doc,
            selectedId: null,
            onSelected: (_) {},
            onOpenSketch: (_) {},
            onEditExtrusion: (_) {},
            onExtrudeSketch: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('No features yet. Create a sketch.'), findsOneWidget);
    final source = historyDocument();
    doc.replaceFeatures(source.features);
    source.dispose();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
