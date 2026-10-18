import '../support/sketch_test_actions.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_editor_controller.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_interaction.dart';

SketchEditorController editorOf(WidgetTester tester) =>
    tester.widget<SketchWorkspace>(find.byType(SketchWorkspace)).editor;
Offset local(WidgetTester tester, double x, double y) {
  final rect = tester.getRect(find.byKey(const Key('sketch-canvas')));
  return rect.topLeft + editorOf(tester).view.project(Vector2(x, y), rect.size);
}

Future<void> point(WidgetTester tester, double x, double y) async {
  await tester.tapAt(local(tester, x, y));
  await tester.pump();
}

Future<void> dimension(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('dimension-input')), value);
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'drawing stages keep the canvas fixed at a compact desktop size',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 550));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: CadScreen()));
      await startSketch(tester);
      final canvas = find.byKey(const Key('sketch-canvas'));
      final original = tester.getRect(canvas);
      await tester.tap(find.byKey(const Key('tool-line')));
      await tester.pump();
      expect(tester.getRect(canvas), original);
      await point(tester, -10, 0);
      expect(tester.getRect(canvas), original);
      await point(tester, 10, 0);
      expect(tester.getRect(canvas), original);
      await tester.tap(find.byKey(const Key('tool-circle')));
      await tester.pump();
      await point(tester, 0, 20);
      expect(tester.getRect(canvas), original);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.getRect(canvas), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draw rectangle and circle, numeric editing, markers, drag cancel, deletion and undo via controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: CadScreen()));
      await startSketch(tester);
      final editor = editorOf(tester);
      await tester.tap(find.byKey(const Key('tool-line')));
      await tester.pump();
      for (final ends in [
        [-30.0, -20.0, 30.0, -20.0],
        [30.0, -20.0, 30.0, 20.0],
        [30.0, 20.0, -30.0, 20.0],
        [-30.0, 20.0, -30.0, -20.0],
      ]) {
        await point(tester, ends[0], ends[1]);
        await point(tester, ends[2], ends[3]);
      }
      expect(editor.definition!.segments, hasLength(4));
      expect(editor.regions!.regions, hasLength(1));
      await tester.tap(find.byKey(const Key('tool-circle')));
      await tester.pump();
      await point(tester, 50, 0);
      await tester.enterText(find.byKey(const Key('drawing-dimension')), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        editor.definition!.circles.values.single.radius,
        closeTo(10, 1e-7),
      );
      expect(find.textContaining('2 filled regions'), findsOneWidget);
      final before = editor.definition;
      await tester.tap(find.byKey(const Key('tool-line')));
      await point(tester, 60, -30);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(editor.anchor, isNull);
      expect(editor.definition, before);
      await tester.tap(find.byKey(const Key('tool-select')));
      await tester.pump();
      await point(tester, 0, -20);
      await tester.ensureVisible(find.text('Horizontal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Horizontal'));
      await tester.pump();
      await tester.ensureVisible(find.text('Length'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Length'));
      await tester.pumpAndSettle();
      await dimension(tester, '60');
      expect(
        editor.definition!.constraints.values.any(
          (c) => c.kind == SketchConstraintKind.horizontal,
        ),
        isTrue,
      );
      expect(editor.solution!.isValid, isTrue);
      final length = editor.definition!.constraints.values.firstWhere(
        (c) => c.kind == SketchConstraintKind.lineLength,
      );
      editor.selectConstraint(length.id);
      await tester.pump();
      final edit = find.byTooltip('Edit dimension');
      await tester.ensureVisible(edit.last);
      await tester.pumpAndSettle();
      await tester.tap(edit.last);
      await tester.pumpAndSettle();
      await dimension(tester, '70');
      expect(editor.definition!.constraints[length.id]!.values.single, 70);
      final line = editor.definition!.segments.values.first;
      final p = editor.solution!.geometry!.points[line.startPointId]!.position;
      final snapshot = editor.definition;
      final gesture = await tester.startGesture(local(tester, p.x, p.y));
      await gesture.moveBy(const Offset(35, 15));
      await tester.pump();
      expect(editor.interaction, SketchInteraction.dragging);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(editor.definition, snapshot);
      expect(editor.document.hasActiveTransaction, isFalse);
      // Escape consumed the drag: releasing must not start or commit a new edit.
      final circle = editor.definition!.circles.values.single;
      final center =
          editor.solution!.geometry!.points[circle.centerPointId]!.position;
      await point(tester, center.x, center.y - circle.radius);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(editor.definition!.circles, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editor.definition!.circles, hasLength(1));
      expect(editor.selected, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'plane creation, reopening, zoom and finish restore previous CAD camera',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CadScreen()));
      final scene = tester.widget<CadScene>(find.byType(CadScene));
      final initial = scene.cameraConfig;
      final cursor = tester.getCenter(find.byType(CadScene));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: cursor),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: cursor,
          pan: const Offset(10, 20),
          panDelta: const Offset(10, 20),
          scale: 1.5,
        ),
      );
      await tester.sendEventToBinding(PointerPanZoomEndEvent(position: cursor));
      await tester.pump();
      final previous = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      expect(previous, isNot(initial));
      await startSketch(tester, plane: PrincipalPlane.yz);
      final editor = editorOf(tester);
      expect(editor.support!.frame.normal, Vector3(1, 0, 0));
      final id = editor.activeId!;
      final canvas = tester.getRect(find.byKey(const Key('sketch-canvas')));
      final scale = editor.view.scale;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: canvas.center,
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pump();
      expect(editor.view.scale, greaterThan(scale));
      await tester.tap(find.byKey(const Key('finish-sketch')));
      await tester.pump();
      expect(
        tester.widget<CadScene>(find.byType(CadScene)).cameraConfig,
        previous,
      );
      await tester.ensureVisible(find.byKey(Key('open-${id.value}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('open-${id.value}')));
      await tester.pumpAndSettle();
      expect(editorOf(tester).activeId, id);
      await tester.tap(find.byKey(const Key('finish-sketch')));
      await tester.pump();
      expect(
        tester.widget<CadScene>(find.byType(CadScene)).cameraConfig,
        previous,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visible named planar face creates an attached sketch and refreshes on document updates',
    (tester) async {
      final cubeId = FeatureId('cube');
      final document = DocumentController(
        evaluators: {
          CubeFeature.type: CubeFeature.evaluate,
          SketchFeature.type: SketchFeature.evaluate,
        },
        features: [
          FeatureDefinition(
            id: cubeId,
            type: CubeFeature.type,
            parameters: {'x': 15, 'y': 16, 'z': 19, 'size': 20},
          ),
        ],
      );
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      await tester.tap(find.byKey(const Key('start-sketch')));
      await tester.pump();
      final scene = tester.widget<CadScene>(find.byType(CadScene));
      final rect = tester.getRect(find.byType(CadScene));
      final projection = CameraProjection(scene.cameraConfig);
      final screen = projection.project(
        projection.toCameraSpace(Vector3(15, 16, 29)),
        screen: rect.size,
      );
      await tester.tapAt(rect.topLeft + Offset(screen.x, screen.y));
      await tester.pumpAndSettle();
      final editor = editorOf(tester);
      expect(editor.definition!.support.reference!.featureId, cubeId);
      final origin = editor.support!.frame.origin;
      document.updateParameters(cubeId, {'z': 39});
      await tester.pump();
      expect(editor.support!.frame.origin.z, origin.z + 20);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dimension validation and cancellation leave history unchanged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: CadScreen()));
    await startSketch(tester);
    await tester.tap(find.byKey(const Key('tool-line')));
    await tester.pump();
    await point(tester, -20, 0);
    await point(tester, 20, 0);
    final editor = editorOf(tester);
    final count = editor.document.undoCount;
    await tester.tap(find.byKey(const Key('tool-select')));
    await tester.pump();
    await point(tester, 0, 0);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Length'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Length'));
    await tester.pumpAndSettle();
    await dimension(tester, 'NaN');
    expect(find.text('Enter a positive finite value.'), findsOneWidget);
    expect(editor.document.undoCount, count);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(editor.definition!.constraints, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
