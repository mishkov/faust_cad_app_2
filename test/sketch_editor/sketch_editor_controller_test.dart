import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_editor_controller.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_interaction.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_hit.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_view.dart';

import '../support/attachment_fixtures.dart' as fixtures;

const viewport = Size(1000, 800);
void tap(SketchEditorController editor, double x, double y) =>
    editor.tap(editor.view.project(Vector2(x, y), viewport), viewport);
void line(
  SketchEditorController editor,
  double x,
  double y,
  double a,
  double b,
) {
  editor.setTool(SketchTool.line);
  tap(editor, x, y);
  tap(editor, a, b);
}

void rectangle(SketchEditorController editor) {
  line(editor, 0, 0, 40, 0);
  line(editor, 40, 0, 40, 30);
  line(editor, 40, 30, 0, 30);
  line(editor, 0, 30, 0, 0);
}

void select(SketchEditorController editor, Iterable<SketchEntityId> ids) {
  editor.setTool(SketchTool.select);
  for (final id in ids) {
    editor.selectEntity(id, additive: true);
  }
}

void main() {
  late DocumentController document;
  late SketchEditorController editor;
  setUp(() {
    document = DocumentController(
      evaluators: {SketchFeature.type: SketchFeature.evaluate},
    );
    editor = SketchEditorController(document);
    editor.create(const PlanarSupport.principal(PrincipalPlane.xy));
  });
  tearDown(() {
    editor.dispose();
    document.dispose();
  });

  test('draw rectangle and dimensioned circle, cancel drawing, delete, undo and reopen', () {
    rectangle(editor);
    expect(editor.definition!.segments, hasLength(4));
    expect(editor.definition!.constraints, isEmpty);
    expect(editor.regions!.regions.single.area, closeTo(1200, 1e-8));
    expect(document.undoCount, 5);
    expect(document.evaluation.materializeGeometry().geometry, isEmpty);
    editor.setTool(SketchTool.circle);
    tap(editor, -20, 20);
    expect(editor.interaction, SketchInteraction.circleRadius);
    editor.hover(editor.view.project(Vector2(-12, 20), viewport), viewport);
    editor.finishDrawing(dimension: 8);
    expect(editor.definition!.circles.values.single.radius, closeTo(8, 1e-7));
    expect(
      editor.definition!.constraints.values.single.kind,
      SketchConstraintKind.radius,
    );
    expect(editor.regions!.regions, hasLength(2));
    final id = editor.activeId!;
    final before = editor.definition!;
    final history = document.undoCount;
    editor.setTool(SketchTool.line);
    tap(editor, 60, 60);
    editor.hover(editor.view.project(Vector2(80, 60), viewport), viewport);
    editor.cancel();
    expect(editor.definition, before);
    expect(document.undoCount, history);
    final circle = editor.definition!.circles.values.single;
    select(editor, [circle.id]);
    editor.deleteSelection();
    expect(editor.definition!.circles, isEmpty);
    expect(
      editor.definition!.points.containsKey(circle.centerPointId),
      isFalse,
    );
    expect(editor.definition!.constraints, isEmpty);
    expect(editor.regions!.regions, hasLength(1));
    editor.undo();
    expect(editor.definition, before);
    expect(editor.selected, isEmpty);
    editor.redo();
    expect(editor.definition!.circles, isEmpty);
    editor.undo();
    editor.close();
    editor.open(id);
    expect(editor.definition, before);
    expect(editor.regions!.regions, hasLength(2));
  });

  test('agreed rectangle relations, dimension editing and constrained drag are undoable', () {
    rectangle(editor);
    final lines = editor.definition!.segments.values.toList();
    for (var i = 0; i < 4; i++) {
      select(editor, [lines[i].endPointId, lines[(i + 1) % 4].startPointId]);
      editor.addConstraint(SketchConstraintKind.coincident);
      select(editor, [lines[i].id]);
      editor.addConstraint(
        i.isEven
            ? SketchConstraintKind.horizontal
            : SketchConstraintKind.vertical,
      );
    }
    select(editor, [lines[0].id]);
    editor.addConstraint(SketchConstraintKind.lineLength, dimension: 40);
    select(editor, [lines[1].id]);
    editor.addConstraint(SketchConstraintKind.lineLength, dimension: 30);
    expect(editor.solution!.degreesOfFreedom, 2);
    final dimension = editor.definition!.constraints.values.firstWhere(
      (c) => c.kind == SketchConstraintKind.lineLength,
    );
    editor.editDimension(dimension.id, 50);
    expect(editor.regions!.regions.single.area, closeTo(1500, 1e-5));
    final before = editor.definition!;
    final count = document.undoCount;
    final point = editor.solution!.geometry!.points[lines[0].startPointId]!;
    editor.beginDrag(point.id, point.position);
    editor.updateDrag(point.position + Vector2(5, 8));
    editor.updateDrag(point.position + Vector2(10, 12));
    expect(document.undoCount, count);
    expect(document.canUndo, isFalse);
    expect(editor.solution!.isValid, isTrue);
    editor.endDrag();
    expect(document.undoCount, count + 1);
    expect(editor.regions!.regions.single.area, closeTo(1500, 1e-5));
    editor.undo();
    expect(editor.definition, before);
    editor.redo();
    select(editor, [lines[0].startPointId]);
    editor.addConstraint(SketchConstraintKind.fixedPoint);
    expect(editor.solution!.degreesOfFreedom, 0);
    final fixed = editor.solution!.geometry!.points[lines[0].startPointId]!;
    editor.beginDrag(fixed.id, fixed.position);
    editor.updateDrag(fixed.position + Vector2(100, 100));
    editor.endDrag();
    expect(
      editor.solution!.geometry!.points[fixed.id]!.position.distanceTo(
        fixed.position,
      ),
      lessThan(1e-6),
    );
  });

  test('drag cancellation restores definition, regions and redo without a history entry', () {
    rectangle(editor);
    editor.setTool(SketchTool.circle);
    tap(editor, -20, 0);
    tap(editor, -12, 0);
    editor.undo();
    final before = editor.definition!;
    final history = document.undoCount, redo = document.redoCount;
    final line = before.segments.values.first;
    editor.setTool(SketchTool.select);
    editor.beginDrag(line.id, Vector2(20, 0));
    editor.updateDrag(Vector2(25, 8));
    expect(editor.definition, isNot(before));
    editor.cancel();
    expect(editor.definition, before);
    expect(document.undoCount, history);
    expect(document.redoCount, redo);
    expect(editor.regions!.regions.single.area, closeTo(1200, 1e-8));
    expect(document.hasActiveTransaction, isFalse);
  });

  test('constraint conflicts expose IDs, withhold cells and recover by removal and undo', () {
    line(editor, 0, 0, 40, 0);
    final id = editor.definition!.segments.keys.single;
    select(editor, [id]);
    editor.addConstraint(SketchConstraintKind.lineLength, dimension: 40);
    editor.addConstraint(SketchConstraintKind.lineLength, dimension: 80);
    expect(editor.solution!.isValid, isFalse);
    expect(editor.regions, isNull);
    expect(
      editor.solution!.diagnostics.any((d) => d.constraintId != null),
      isTrue,
    );
    expect(document.evaluation.dataOutputs, isEmpty);
    final conflict = editor.definition!.constraints.keys.last;
    editor.removeConstraint(conflict);
    expect(editor.solution!.isValid, isTrue);
    editor.undo();
    expect(editor.solution!.isValid, isFalse);
    editor.undo();
    expect(editor.solution!.isValid, isTrue);
  });

  test(
    'pixel snapping never becomes constraints or closes a representable gap',
    () {
      rectangle(editor);
      final p = editor.definition!.points.values.last;
      final gapped = editor.definition!.copyWith(
        points: [
          for (final point in editor.definition!.points.values)
            point.id == p.id
                ? SketchPoint(id: p.id, x: p.x, y: p.y + 1e-5)
                : point,
        ],
      );
      document.setFeature(
        SketchFeature.definition(id: editor.activeId!, sketch: gapped),
      );
      expect(editor.regions!.regions, isEmpty);
      expect(editor.definition!.constraints, isEmpty);
      final local = editor.solution!.geometry!.points.values.first.position;
      for (final scale in [2.0, 20.0]) {
        editor.updateView(SketchView(scale: scale));
        final cursor =
            editor.view.project(local, viewport) + const Offset(9, 0);
        final snap = editor.presentation!.snap(cursor, editor.view, viewport);
        expect(snap.position.distanceTo(local), lessThan(1e-4));
        expect(snap.label, contains('placement only'));
      }
      expect(editor.regions!.regions, isEmpty);
    },
  );

  test('hit priority, overlap cycling, persistent region selection and missing recovery', () {
    rectangle(editor);
    editor.setTool(SketchTool.select);
    final cursor = editor.view.project(Vector2(0, 0), viewport);
    final hits = editor.presentation!.hits(cursor, editor.view, viewport);
    expect(hits.first.kind, SketchHitKind.point);
    editor.tap(cursor, viewport);
    final first = editor.selected.single;
    editor.tap(cursor, viewport, additive: true, cycle: true);
    expect(editor.selected.length, 2);
    expect(editor.selected.contains(first), isTrue);
    tap(editor, 20, 15);
    expect(editor.selectedRegionIds, hasLength(1));
    final before = editor.definition!;
    final p = before.points.values.last;
    document.setFeature(
      SketchFeature.definition(
        id: editor.activeId!,
        sketch: before.copyWith(
          points: [
            for (final point in before.points.values)
              point.id == p.id ? SketchPoint(id: p.id, x: 0.1, y: 0) : point,
          ],
        ),
      ),
    );
    expect(editor.selectedRegionIds, isEmpty);
    expect(editor.profileDiagnostic, contains('missing'));
    editor.undo();
    expect(editor.selectedRegionIds, hasLength(1));
    editor.redo();
    expect(editor.selectedRegionIds, isEmpty);
  });

  test(
    'delete point cascades primitives and constraints, keeps retained IDs',
    () {
      rectangle(editor);
      final line = editor.definition!.segments.values.first;
      select(editor, [line.id]);
      editor.addConstraint(SketchConstraintKind.horizontal);
      final before = editor.definition!;
      select(editor, [line.startPointId]);
      editor.deleteSelection();
      expect(editor.definition!.segments.containsKey(line.id), isFalse);
      expect(editor.definition!.constraints, isEmpty);
      expect(editor.definition!.retiredIds, contains(line.id));
      expect(editor.selected, isEmpty);
      editor.undo();
      expect(editor.definition, before);
    },
  );

  test('principal planes reopen with the same local geometry', () {
    for (final plane in PrincipalPlane.values) {
      final id = editor.create(PlanarSupport.principal(plane));
      rectangle(editor);
      final before = editor.definition;
      editor.close();
      editor.open(id);
      expect(editor.definition, before);
      expect(editor.regions!.regions.single.area, closeTo(1200, 1e-8));
      expect(editor.support!.frame.normal, switch (plane) {
        PrincipalPlane.xy => Vector3(0, 0, 1),
        PrincipalPlane.xz => Vector3(0, -1, 0),
        PrincipalPlane.yz => Vector3(1, 0, 0),
      });
    }
  });

  test('attached sketch extends past trim, follows rotated/reversed support, handles broken support and undo', () {
    final supportId = FeatureId('support');
    final doc = DocumentController(
      evaluators: {
        SketchFeature.type: SketchFeature.evaluate,
        'plane': (d, c) => [
          if (d.parameters['missing'] != true)
            FeatureOutput(
              key: 'face',
              kind: OutputKind.face,
              geometry: d.parameters['reversed'] == true
                  ? rectangleFace(d).reversed()
                  : rectangleFace(d),
            ),
        ],
      },
      features: [
        FeatureDefinition(
          id: supportId,
          type: 'plane',
          parameters: {'height': 2, 'angle': 0},
        ),
      ],
    );
    final attached = SketchEditorController(doc);
    addTearDown(() {
      attached.dispose();
      doc.dispose();
    });
    final id = attached.create(
      PlanarSupport.face(
        reference: OutputReference(
          featureId: supportId,
          key: 'face',
          kind: OutputKind.face,
        ),
        preferredDirection: Vector3(1, 0, 0),
      ),
    );
    rectangle(attached);
    expect(attached.regions!.regions.single.area, closeTo(1200, 1e-8));
    final authored = attached.definition;
    doc.updateParameters(supportId, {
      'height': 12,
      'angle': 0.4,
      'reversed': true,
    });
    expect(attached.definition, authored);
    expect(attached.support!.frame.origin.z, 12);
    expect(attached.support!.frame.normal.z, closeTo(-math.cos(0.4), 1e-8));
    attached.close();
    attached.open(id);
    expect(attached.support!.frame.origin.z, 12);
    doc.updateParameters(supportId, {'missing': true});
    expect(attached.support, isNull);
    expect(attached.regions, isNull);
    expect(attached.supportDiagnostic, contains('Broken attachment'));
    attached.undo();
    expect(attached.support, isNotNull);
    expect(attached.regions!.regions, hasLength(1));
  });

  test('all selection-based relation controls use the agreed kinds and solve correctly', () {
    line(editor, -40, 0, 0, 0);
    line(editor, -40, 30, 0, 30);
    final a = editor.definition!.segments.values.first,
        b = editor.definition!.segments.values.last;
    select(editor, [a.id, b.id]);
    expect(
      editor.availableConstraints,
      containsAll([
        SketchConstraintKind.parallel,
        SketchConstraintKind.perpendicular,
        SketchConstraintKind.equalLengths,
      ]),
    );
    editor.addConstraint(SketchConstraintKind.parallel);
    editor.addConstraint(SketchConstraintKind.equalLengths);
    expect(editor.solution!.isValid, isTrue);
    final length = editor.solution!.geometry!.points[a.endPointId]!.position
        .distanceTo(
          editor.solution!.geometry!.points[a.startPointId]!.position,
        );
    select(editor, [a.startPointId, a.endPointId]);
    editor.addConstraint(SketchConstraintKind.distance, dimension: length);
    expect(editor.solution!.isValid, isTrue);
    select(editor, [b.startPointId, a.id]);
    editor.addConstraint(SketchConstraintKind.pointOnLine);
    expect(editor.solution!.isValid, isTrue);
    editor.undo();
    final parallel = editor.definition!.constraints.values.firstWhere(
      (c) => c.kind == SketchConstraintKind.parallel,
    );
    editor.removeConstraint(parallel.id);
    select(editor, [a.id, b.id]);
    editor.addConstraint(SketchConstraintKind.perpendicular);
    expect(editor.solution!.isValid, isTrue);
    final solved = editor.solution!.geometry!;
    final u =
        solved.points[a.endPointId]!.position -
        solved.points[a.startPointId]!.position;
    final v =
        solved.points[b.endPointId]!.position -
        solved.points[b.startPointId]!.position;
    expect(u.normalized().dot(v.normalized()).abs(), lessThan(1e-6));
  });

  test('circle relations, center/primitive dragging, dimensions and fixed primitives', () {
    editor.setTool(SketchTool.circle);
    tap(editor, -30, 0);
    tap(editor, -20, 0);
    editor.setTool(SketchTool.circle);
    tap(editor, 30, 0);
    tap(editor, 40, 0);
    final a = editor.definition!.circles.values.first,
        b = editor.definition!.circles.values.last;
    select(editor, [a.id]);
    expect(
      editor.availableConstraints,
      containsAll([
        SketchConstraintKind.radius,
        SketchConstraintKind.diameter,
        SketchConstraintKind.fixedPrimitive,
      ]),
    );
    editor.addConstraint(SketchConstraintKind.diameter, dimension: 24);
    select(editor, [a.id, b.id]);
    editor.addConstraint(SketchConstraintKind.equalRadii);
    expect(editor.solution!.geometry!.circles[a.id]!.radius, closeTo(12, 1e-6));
    expect(editor.solution!.geometry!.circles[b.id]!.radius, closeTo(12, 1e-6));
    final center = editor.solution!.geometry!.points[a.centerPointId]!.position;
    select(editor, [a.id]);
    editor.beginDrag(a.id, center + Vector2(12, 0));
    editor.updateDrag(center + Vector2(18, 8));
    editor.endDrag();
    expect(
      editor.solution!.geometry!.points[a.centerPointId]!.position.distanceTo(
        center,
      ),
      greaterThan(1),
    );
    expect(editor.solution!.geometry!.circles[a.id]!.radius, closeTo(12, 1e-6));
    select(editor, [a.id]);
    editor.addConstraint(SketchConstraintKind.fixedPrimitive);
    final fixed = editor.solution!.geometry!.points[a.centerPointId]!.position;
    editor.beginDrag(a.centerPointId, fixed);
    editor.updateDrag(fixed + Vector2(100, 100));
    editor.endDrag();
    expect(
      editor.solution!.geometry!.points[a.centerPointId]!.position.distanceTo(
        fixed,
      ),
      lessThan(1e-6),
    );
    select(editor, [b.centerPointId, a.id]);
    editor.addConstraint(SketchConstraintKind.pointOnCircle);
    expect(editor.solution!.isValid, isTrue);
    expect(
      editor.solution!.geometry!.points[b.centerPointId]!.position.distanceTo(
        fixed,
      ),
      closeTo(12, 1e-6),
    );
  });

  test('numeric drawing commits length and a dimension as one undo entry; invalid input is reversible', () {
    final count = document.undoCount;
    editor.setTool(SketchTool.line);
    tap(editor, 0, 0);
    editor.finishDrawing(dimension: double.infinity);
    expect(editor.definition!.segments, isEmpty);
    expect(document.undoCount, count);
    editor.hover(editor.view.project(Vector2(10, 10), viewport), viewport);
    editor.finishDrawing(dimension: 20);
    final solved = editor.solution!.geometry!;
    final line = solved.segments.values.single;
    expect(
      solved.points[line.startPointId]!.position.distanceTo(
        solved.points[line.endPointId]!.position,
      ),
      closeTo(20, 1e-6),
    );
    expect(
      editor.definition!.constraints.values.single.kind,
      SketchConstraintKind.lineLength,
    );
    expect(document.undoCount, count + 1);
    editor.undo();
    expect(editor.definition!.segments, isEmpty);
    expect(editor.definition!.constraints, isEmpty);
  });
}

// Reuse the analytic planar attachment fixture, including arbitrary plane axes.
Face rectangleFace(FeatureDefinition d) => fixtures.rectangle(
  fixtures.tiltedFrame(
    (d.parameters['angle'] as num).toDouble(),
    height: (d.parameters['height'] as num).toDouble(),
  ),
);
