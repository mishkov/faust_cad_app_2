import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/feature_history/feature_history.dart';
import 'package:faust_cad_app_2/extrusion_editor/extrusion_editor_controller.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../support/extrusion_validation.dart';
import '../support/feature_history_fixtures.dart';
import '../support/linked_extrusion_fixtures.dart';

Map<FeatureId, double> volumes(DocumentController doc) => {
  for (final entry in doc.evaluation.materializeGeometry().bodies.entries)
    entry.value.featureId: analyticBoundaryVolume(
      entry.key as Solid,
      PlanarFrame.xy(),
    ),
};

void main() {
  test(
    'authored order differs from dependency order and survives replacement',
    () {
      final doc = historyDocument();
      addTearDown(doc.dispose);
      final order = doc.features.map((f) => f.id).toList();
      expect(doc.evaluation.evaluationOrder, isNot(order));
      doc.updateParameters(linkedExtrusionId, {'distance': 9});
      expect(doc.features.map((f) => f.id), order);
      doc.undo();
      doc.redo();
      expect(doc.features.map((f) => f.id), order);
      final headless = CadDocument(
        evaluators: historyEvaluators,
        features: doc.features,
      );
      headless.setFeature(doc.features.first);
      expect(headless.features.map((f) => f.id), order);
    },
  );

  test('early sketch edit rebuilds branched extrusions and multiple attachment levels atomically', () {
    final doc = historyDocument();
    addTearDown(doc.dispose);
    final originalVolumes = volumes(doc);
    final bodyRefs = doc.evaluation.materializeGeometry().bodies.values.toSet();
    final independent = doc.evaluation.features[independentId];
    final editor = SketchEditorController(doc)..open(linkedSketchId);
    addTearDown(editor.dispose);
    var publications = 0;
    void observe() {
      publications++;
      expect(
        doc.evaluation.features.values.every(
          (f) => f.state == FeatureState.valid,
        ),
        true,
      );
      expect(
        volumes(doc)[linkedExtrusionId],
        closeTo(originalVolumes[linkedExtrusionId]!, 1e-6),
      );
      if (publications == 1) return;
      expect(
        doc.evaluation.features[capSketchId]!.support!.boundary!.outerWire.edges
            .map((e) => e.begin.vector.x)
            .reduce(math.min),
        closeTo(4, 1e-6),
      );
      expect(
        doc.evaluation.features[laterSketchId]!.support!.frame.origin.z,
        closeTo(7, 1e-6),
      );
    }

    doc.addListener(observe);
    editor.beginDrag(SketchEntityId('p0-0'), Vector2(0, 0));
    // Move all points together through the existing document API while retaining
    // every authored entity/profile reference. A single command publishes all levels.
    final authored = rectangles();
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: authored
          .copyWith(
            points: [
              for (final p in authored.points.values)
                SketchPoint(id: p.id, x: p.x + 4, y: p.y + 2),
            ],
          )
          .toParameters(),
    });
    editor.endDrag();
    expect(publications, 3); // Begin, coherent preview, commit.
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
    expect(
      doc.evaluation.materializeGeometry().bodies.values.toSet(),
      bodyRefs,
    );
    doc.removeListener(observe);
  });

  test('shape and extrusion edits undo/redo parameters references and analytic geometry', () {
    final doc = historyDocument();
    addTearDown(doc.dispose);
    final original = doc.features;
    final before = volumes(doc);
    final originalRefs = doc.evaluation
        .materializeGeometry()
        .bodies
        .values
        .toSet();
    final independent = doc.evaluation.features[independentId];
    final shape = rectangles();
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: shape
          .copyWith(
            points: [
              for (final p in shape.points.values)
                SketchPoint(id: p.id, x: p.x * 2, y: p.y),
            ],
          )
          .toParameters(),
    });
    expect(volumes(doc)[linkedExtrusionId], closeTo(120, 1e-6));
    expect(volumes(doc)[branchExtrusionId], closeTo(72, 1e-6));
    expect(volumes(doc)[laterExtrusionId], closeTo(math.pi * 8, 1e-6));
    final expanded = doc.features;
    doc.updateParameters(linkedExtrusionId, {'distance': 8, 'reverse': true});
    expect(doc.evaluation.features[capSketchId]!.support!.frame.origin.z, -8);
    expect(
      doc.evaluation.features[laterSketchId]!.support!.frame.origin.z,
      -10,
    );
    expect(volumes(doc)[linkedExtrusionId], closeTo(192, 1e-6));
    final edited = doc.features;
    doc.undo();
    expect(doc.features, expanded);
    expect(doc.evaluation.features[capSketchId]!.support!.frame.origin.z, 5);
    doc.undo();
    expect(doc.features, original);
    for (final entry in before.entries) {
      expect(volumes(doc)[entry.key], closeTo(entry.value, 1e-6));
    }
    doc.redo();
    doc.redo();
    expect(doc.features, edited);
    expect(
      doc.evaluation.features[laterSketchId]!.support!.frame.origin.z,
      -10,
    );
    expect(
      doc.evaluation.materializeGeometry().bodies.values.toSet(),
      originalRefs,
    );
    expect(doc.evaluation.features[independentId], same(independent));
    for (var i = 0; i < original.length; i++) {
      expect(doc.features[i].id, original[i].id);
      expect(doc.features[i].inputs, original[i].inputs);
      expect(doc.features[i].support, original[i].support);
      expect(
        doc.features[i].parameters['profiles'],
        original[i].parameters['profiles'],
      );
    }
  });

  test('missing profiles and broken attachments withhold stale bodies but preserve independent output', () {
    final doc = historyDocument();
    addTearDown(doc.dispose);
    final before = doc.features;
    final independent = doc.evaluation.features[independentId];
    final shape = rectangles();
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: shape
          .copyWith(segments: shape.segments.values.skip(1))
          .toParameters(),
    });
    for (final id in [linkedExtrusionId, branchExtrusionId]) {
      final result = doc.evaluation.features[id]!;
      expect(result.state, FeatureState.failed);
      expect(result.diagnostics['profileStatus'], 'missing');
      expect(result.diagnosticOutputs, isNotEmpty);
    }
    expect(
      doc.evaluation.features[capSketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(
      doc.evaluation.features[laterExtrusionId]!.state,
      FeatureState.blocked,
    );
    expect(
      doc.evaluation.features[laterSketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(
      doc.evaluation.materializeGeometry().bodies.values.map(
        (r) => r.featureId,
      ),
      [independentId],
    );
    expect(doc.evaluation.features[independentId], same(independent));
    doc.undo();
    expect(doc.features, before);
    expect(doc.evaluation.materializeGeometry().bodies, hasLength(4));
    doc.redo();
    expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
  });

  test('deleting one feature retains transitive dependents and undo restores references', () {
    final doc = historyDocument();
    addTearDown(doc.dispose);
    final before = doc.features;
    final expected = [
      linkedExtrusionId,
      branchExtrusionId,
      capSketchId,
      laterExtrusionId,
      laterSketchId,
    ];
    expect(
      FeatureHistory.affectedDependents(
        doc.features,
        linkedSketchId,
      ).map((f) => f.id),
      expected,
    );
    doc.removeFeature(linkedSketchId);
    expect(doc.features.map((f) => f.id), [...expected, independentId]);
    expect(
      doc.evaluation.features[linkedExtrusionId]!.issue,
      FeatureIssue.missingDependency,
    );
    expect(
      doc.evaluation.features[capSketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
    doc.undo();
    expect(doc.features, before);
    expect(doc.evaluation.materializeGeometry().bodies, hasLength(4));
    doc.redo();
    expect(doc.features, before.skip(1));
  });

  test(
    'rename is undoable and survives both editors without losing metadata',
    () {
      final doc = historyDocument();
      addTearDown(doc.dispose);
      doc.renameFeature(linkedSketchId, '  Renamed profile  ');
      expect(doc.features.first.name, 'Renamed profile');
      expect(
        () => doc.renameFeature(linkedSketchId, '  '),
        throwsArgumentError,
      );
      expect(doc.undoCount, 1);
      doc.undo();
      expect(doc.features.first.name, 'Base profile');
      doc.redo();
      final editor = SketchEditorController(doc)..open(linkedSketchId);
      addTearDown(editor.dispose);
      editor.selectEntity(SketchEntityId('p0-0'));
      editor.deleteSelection();
      expect(doc.features.first.name, 'Renamed profile');
      doc.undo();
      doc.renameFeature(linkedExtrusionId, 'Boss');
      final feature = doc.features.firstWhere((f) => f.id == linkedExtrusionId);
      final extrusion = ExtrusionEditorController(doc)..open(linkedExtrusionId);
      addTearDown(extrusion.dispose);
      extrusion.setDistance('9');
      expect(extrusion.confirm(), true);
      final after = doc.features.firstWhere((f) => f.id == linkedExtrusionId);
      expect(after.name, 'Boss');
      expect(after.inputs, feature.inputs);
      expect(after.dependencies, feature.dependencies);
      expect(after.parameters['profiles'], feature.parameters['profiles']);
      doc.undo();
      expect(
        doc.features.firstWhere((f) => f.id == linkedExtrusionId),
        feature,
      );
    },
  );

  test('new editors never reuse deleted or undone feature IDs', () {
    final doc = historyDocument();
    addTearDown(doc.dispose);
    final id = doc.allocateFeatureId('sketch');
    expect(id, FeatureId('sketch-1'));
    expect(doc.undoCount, 0);
    doc.addFeature(SketchFeature.definition(id: id, sketch: rectangles()));
    final extrusion = ExtrusionEditorController(doc);
    addTearDown(extrusion.dispose);
    extrusion.create(
      id,
      regionIds: [regionsOf(rectangles()).regions.single.id],
    );
    final extrudeId = extrusion.activeId!;
    expect(extrusion.confirm(), true);
    doc.removeFeature(id);
    final editor = SketchEditorController(doc);
    addTearDown(editor.dispose);
    final newId = editor.create(rectangles().support);
    expect(newId, isNot(id));
    expect(
      doc.evaluation.features[extrudeId]!.issue,
      FeatureIssue.missingDependency,
    );
    doc.undo();
    final anotherId = editor.create(rectangles().support);
    expect(anotherId, isNot(anyOf(id, newId)));
    doc.removeFeature(extrudeId);
    extrusion.create(linkedSketchId);
    expect(extrusion.activeId, isNot(extrudeId));
    extrusion.cancel();
    final next = ExtrusionEditorController(doc);
    addTearDown(next.dispose);
    next.create(linkedSketchId);
    expect(next.activeId, FeatureId('extrude-3'));
    next.cancel();
  });

  test('impact traversal terminates on cycles and missing producers', () {
    final a = FeatureId('a'),
        b = FeatureId('b'),
        missing = FeatureId('missing');
    final features = [
      FeatureDefinition(id: b, type: CubeFeature.type, dependencies: {a}),
      FeatureDefinition(
        id: a,
        type: CubeFeature.type,
        dependencies: {b, missing},
      ),
    ];
    expect(FeatureHistory.affectedDependents(features, missing), features);
    expect(FeatureHistory.affectedDependents(features, a), [features.first]);
  });
}
