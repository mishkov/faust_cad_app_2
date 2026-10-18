import 'dart:convert';

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/extrusion_editor/extrusion_workspace.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../support/linked_extrusion_fixtures.dart';

void main() {
  for (final shape in [
    ('rectangle', rectangles()),
    ('circle', circles()),
    ('annulus', circles(annulus: true)),
    ('united overlap', rectangles(secondX: 2, secondY: 1)),
    ('separate solids', rectangles(secondX: 10)),
  ]) {
    testWidgets(
      '${shape.$1}: multiselection preview confirm edit cancel undo redo',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final doc = linkedDocument(shape.$2, withExtrusion: false);
        addTearDown(doc.dispose);
        await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
        await tester.ensureVisible(
          find.byKey(Key('extrude-${linkedSketchId.value}')),
        );
        await tester.tap(find.byKey(Key('extrude-${linkedSketchId.value}')));
        await tester.pump();
        final editor = tester
            .widget<ExtrusionWorkspace>(find.byType(ExtrusionWorkspace))
            .editor;
        final id = editor.activeId!;
        expect(doc.undoCount, 0);
        for (final region in editor.regions!.regions) {
          if (shape.$1 == 'annulus' && region.holes.isEmpty) continue;
          final finder = find.byKey(Key('extrusion-region-${region.id}'));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pump();
        }
        expect(editor.canConfirm, true);
        expect(
          doc.evaluation.materializeGeometry().bodies,
          hasLength(shape.$1 == 'separate solids' ? 2 : 1),
        );
        expect(doc.undoCount, 0);
        await tester.ensureVisible(find.byKey(const Key('extrusion-distance')));
        await tester.enterText(
          find.byKey(const Key('extrusion-distance')),
          'NaN',
        );
        await tester.pump();
        expect(doc.evaluation.materializeGeometry().bodies, isEmpty);
        expect(editor.canConfirm, false);
        await tester.enterText(
          find.byKey(const Key('extrusion-distance')),
          '1e308',
        );
        await tester.pump();
        expect(editor.canConfirm, false);
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const Key('extrusion-distance')),
          '8',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('extrusion-reverse')));
        await tester.pump();
        expect(editor.reverse, true);
        await tester.tap(find.byKey(const Key('confirm-extrusion')));
        await tester.pump();
        expect(doc.undoCount, 1);
        expect(doc.features.last.parameters['distance'], 8);
        expect(doc.features.last.parameters['reverse'], true);
        await tester.ensureVisible(find.byKey(Key('edit-${id.value}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit-${id.value}')));
        await tester.pump();
        expect(editor.selectedRegionIds, isNotEmpty);
        await tester.enterText(
          find.byKey(const Key('extrusion-distance')),
          '15',
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(doc.features.last.parameters['distance'], 8);
        await tester.ensureVisible(find.byKey(Key('edit-${id.value}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit-${id.value}')));
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('extrusion-distance')),
          '12',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('confirm-extrusion')));
        await tester.pump();
        expect(doc.undoCount, 2);
        await tester.tap(find.byTooltip('Undo'));
        await tester.pump();
        expect(doc.features.last.parameters['distance'], 8);
        await tester.tap(find.byTooltip('Redo'));
        await tester.pump();
        expect(doc.features.last.parameters['distance'], 12);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'sketch region selection starts extrusion, cap picking attaches second sketch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = linkedDocument(rectangles(), withExtrusion: false);
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
      await tester.tap(find.byKey(Key('open-${linkedSketchId.value}')));
      await tester.pumpAndSettle();
      final sketchEditor = tester
          .widget<SketchWorkspace>(find.byType(SketchWorkspace))
          .editor;
      sketchEditor.selectHit(
        sketchEditor.presentation!
            .hits(
              sketchEditor.view.project(Vector2(2, 1.5), const Size(820, 550)),
              sketchEditor.view,
              const Size(820, 550),
            )
            .last,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('extrude-sketch')));
      await tester.pump();
      final editor = tester
          .widget<ExtrusionWorkspace>(find.byType(ExtrusionWorkspace))
          .editor;
      expect(editor.selectedRegionIds, hasLength(1));
      final profileCanvas = find.byKey(const Key('extrusion-profile-canvas'));
      await tester.tapAt(tester.getCenter(profileCanvas));
      await tester.pump();
      expect(editor.selectedRegionIds, isEmpty);
      await tester.tapAt(tester.getCenter(profileCanvas));
      await tester.pump();
      expect(editor.selectedRegionIds, hasLength(1));
      await tester.tap(find.byKey(const Key('confirm-extrusion')));
      await tester.pump();
      final id = doc.features.last.id;
      await tester.tap(find.byKey(const Key('start-sketch')));
      await tester.pump();
      final scene = tester.widget<CadScene>(find.byType(CadScene));
      final rect = tester.getRect(find.byType(CadScene));
      final projection = CameraProjection(scene.cameraConfig);
      final p = projection.project(
        projection.toCameraSpace(Vector3(2, 1.5, 10)),
        screen: rect.size,
      );
      await tester.tapAt(rect.topLeft + Offset(p.x, p.y));
      await tester.pumpAndSettle();
      final second = tester
          .widget<SketchWorkspace>(find.byType(SketchWorkspace))
          .editor;
      expect(second.definition!.support.reference!.featureId, id);
      expect(
        jsonDecode(second.definition!.support.reference!.key)[3],
        'endCap',
      );
      final secondId = second.activeId!;
      doc.updateParameters(id, {'distance': 14, 'reverse': true});
      await tester.pump();
      expect(second.support!.frame.origin.z, -14);
      expect(doc.evaluation.features[secondId]!.state, FeatureState.valid);
      doc.updateParameters(linkedSketchId, {
        SketchFeature.parameterKey: rectangles()
            .copyWith(
              points: [
                for (final p in rectangles().points.values)
                  SketchPoint(id: p.id, x: p.x * 2, y: p.y),
              ],
            )
            .toParameters(),
      });
      await tester.pump();
      expect(second.support!.frame.origin.z, -14);
      expect(second.definition!.support.reference!.featureId, id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'point contact diagnosis disables confirmation and cancel leaves no feature',
    (tester) async {
      final doc = linkedDocument(
        rectangles(secondX: 4, secondY: 3),
        withExtrusion: false,
      );
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: CadScreen(controller: doc)));
      await tester.ensureVisible(
        find.byKey(Key('extrude-${linkedSketchId.value}')),
      );
      await tester.tap(find.byKey(Key('extrude-${linkedSketchId.value}')));
      await tester.pump();
      final editor = tester
          .widget<ExtrusionWorkspace>(find.byType(ExtrusionWorkspace))
          .editor;
      for (final r in editor.regions!.regions) {
        editor.toggleRegion(r.id);
      }
      await tester.pump();
      expect(editor.diagnostics.join(' '), contains('point'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-extrusion')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('cancel-extrusion')));
      await tester.pump();
      expect(doc.features, hasLength(1));
      expect(doc.undoCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
