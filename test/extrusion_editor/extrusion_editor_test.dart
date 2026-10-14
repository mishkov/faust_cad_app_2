import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/extrusion_editor/extrusion_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/linked_extrusion_fixtures.dart';

void main() {
  test(
    'preview confirm cancel and reopening coalesce edits and preserve redo',
    () {
      final doc = linkedDocument(rectangles(), withExtrusion: false);
      final editor = ExtrusionEditorController(doc);
      addTearDown(doc.dispose);
      addTearDown(editor.dispose);
      editor.create(linkedSketchId);
      final id = editor.activeId!;
      expect(doc.undoCount, 0);
      expect(editor.canConfirm, false);
      editor.toggleRegion(editor.regions!.regions.single.id);
      editor.setDistance('12');
      editor.setReverse(true);
      expect(doc.undoCount, 0);
      expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
      expect(editor.confirm(), true);
      expect(doc.undoCount, 1);
      expect(doc.undoLabel, 'Create extrusion');
      doc.undo();
      expect(doc.features, hasLength(1));
      doc.redo();
      expect(doc.features.last.parameters['distance'], 12);
      editor.open(id);
      editor.setDistance('9');
      editor.setReverse(false);
      expect(doc.undoCount, 1);
      editor.cancel();
      expect(doc.features.last.parameters['distance'], 12);
      expect(doc.features.last.parameters['reverse'], true);
      editor.open(id);
      expect(editor.distanceText, '12.0');
      expect(editor.selectedRegionIds, hasLength(1));
      editor.setDistance('7');
      editor.setReverse(false);
      editor.confirm();
      expect(doc.undoCount, 2);
      doc.undo();
      expect(doc.features.last.parameters['distance'], 12);
      final redo = doc.redoCount;
      editor.create(linkedSketchId);
      editor.toggleRegion(editor.regions!.regions.single.id);
      editor.cancel();
      expect(doc.redoCount, redo);
      doc.redo();
      expect(doc.features.last.parameters['distance'], 7);
      editor.open(id);
      editor.confirm();
      expect(doc.undoCount, 2);
    },
  );

  test('invalid entry, broken selections and invalid upstream sketch clear preview and can be repaired', () {
    final authored = rectangles();
    final doc = linkedDocument(authored);
    final editor = ExtrusionEditorController(doc);
    addTearDown(doc.dispose);
    addTearDown(editor.dispose);
    editor.open(linkedExtrusionId);
    for (final text in ['', 'NaN', 'Infinity', '-1', '0', 'abc']) {
      editor.setDistance(text);
      expect(editor.canConfirm, false);
      expect(editor.diagnostics.join(' '), contains('positive finite'));
      expect(doc.evaluation.materializeGeometry().bodies, isEmpty);
    }
    editor.setDistance('8');
    expect(editor.canConfirm, true);
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: authored
          .copyWith(segments: authored.segments.values.skip(1))
          .toParameters(),
    });
    expect(editor.selectedRegionIds, isEmpty);
    expect(editor.canConfirm, false);
    expect(doc.evaluation.materializeGeometry().bodies, isEmpty);
    expect(editor.diagnostics.join(' '), contains('missing'));
    editor.cancel();
    expect(doc.features.last.parameters['distance'], 5);
    expect(editor.activeId, isNull);
    editor.open(linkedExtrusionId);
    editor.clearSelection();
    editor.toggleRegion(editor.regions!.regions.single.id);
    expect(editor.canConfirm, true);
    expect(editor.confirm(), true);
    expect(doc.features.last.type, ExtrudeFeature.type);
  });

  test(
    'disposing during preview restores the prior document without history',
    () {
      final doc = linkedDocument(circles(), withExtrusion: false);
      addTearDown(doc.dispose);
      final editor = ExtrusionEditorController(doc);
      editor.create(
        linkedSketchId,
        regionIds: regionsOf(circles()).regions.map((r) => r.id),
      );
      expect(editor.canConfirm, true);
      editor.dispose();
      expect(doc.hasActiveTransaction, false);
      expect(doc.features, hasLength(1));
      expect(doc.undoCount, 0);
    },
  );
}
