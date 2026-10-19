import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/selection/principal_plane_views.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';

import '../support/sketch_test_actions.dart';

void main() {
  testWidgets('plane selection is transient and only Escape cancels it', (
    tester,
  ) async {
    final document = DocumentController(
      evaluators: {SketchFeature.type: SketchFeature.evaluate},
    );
    addTearDown(document.dispose);
    await tester.pumpWidget(MaterialApp(home: CadScreen(controller: document)));
    final scene = find.byType(CadScene);
    final rect = tester.getRect(scene);
    final button = find.byKey(const Key('start-sketch'));
    expect(tester.getCenter(button).dy, rect.center.dy);
    expect(tester.getRect(button).left, rect.left + 12);
    expect(find.text('New sketch'), findsNothing);
    expect(find.byType(DropdownButton<PrincipalPlane>), findsNothing);
    final camera = tester.widget<CadScene>(scene).cameraConfig;
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<CadScene>(scene).showPrincipalPlanes, isTrue);
    final hint = find.byKey(const Key('sketch-plane-hint'));
    expect(hint, findsOneWidget);
    expect(tester.getCenter(hint).dx, closeTo(rect.center.dx, 0.01));
    await tester.tap(button);
    await tester.tapAt(rect.bottomLeft + const Offset(70, -10));
    await tester.pump();
    expect(hint, findsOneWidget);
    expect(document.features, isEmpty);
    expect(document.undoCount, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(hint, findsNothing);
    expect(tester.widget<CadScene>(scene).showPrincipalPlanes, isFalse);
    expect(tester.widget<CadScene>(scene).cameraConfig, camera);
    expect(document.features, isEmpty);
    expect(document.undoCount, 0);
  });

  testWidgets('selecting a plane animates before enabling sketch tools', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CadScreen()));
    final scene = find.byType(CadScene);
    final rect = tester.getRect(scene);
    final initial = tester.widget<CadScene>(scene).cameraConfig;
    await tester.tap(find.byKey(const Key('start-sketch')));
    await tester.pump();
    final projection = CameraProjection(initial);
    final point = projection.project(
      projection.toCameraSpace(
        PrincipalPlaneViews.frame(PrincipalPlane.xy)
            .localToWorld(Vector2(26, 38)),
      ),
      screen: rect.size,
    );
    await tester.tapAt(rect.topLeft + Offset(point.x, point.y));
    await tester.pump();
    expect(find.byKey(const Key('tool-line')), findsNothing);
    await tester.pump(const Duration(milliseconds: 175));
    final middle = tester.widget<CadScene>(scene).cameraConfig;
    expect(middle.pitch, isNot(initial.pitch));
    expect(middle.isOrthographic, isFalse);
    await tester.pumpAndSettle();
    expect(tester.widget<CadScene>(scene).cameraConfig.isOrthographic, isTrue);
    expect(tester.getRect(scene), rect);
    expect(find.byKey(const Key('tool-line')), findsOneWidget);
    expect(find.byKey(const Key('sketch-plane-hint')), findsNothing);
    expect(tester.widget<CadScene>(scene).showPrincipalPlanes, isFalse);
  });

  for (final plane in PrincipalPlane.values) {
    testWidgets(
      '${plane.name} drawing, pan and zoom remain aligned with scene',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: CadScreen()));
        await startSketch(tester, plane: plane);
        final editor = tester
            .widget<SketchWorkspace>(find.byType(SketchWorkspace))
            .editor;
        expect(editor.definition!.support.principalPlane, plane);
        final scene = find.byType(CadScene);
        final rect = tester.getRect(scene);
        void checkAlignment() {
          final camera = tester.widget<CadScene>(scene).cameraConfig;
          expect(camera.isOrthographic, isTrue);
          final projection = CameraProjection(camera);
          final direction = projection.fromCameraDirection(Vector3(0, 1, 0));
          expect(
            direction.dot(editor.support!.frame.normal),
            closeTo(-1, 1e-10),
          );
          for (final local in [
            Vector2.zero(),
            Vector2(7, 11),
            Vector2(-13, 9),
          ]) {
            final p = projection.project(
              projection.toCameraSpace(
                editor.support!.frame.localToWorld(local),
              ),
              screen: rect.size,
            );
            final expected = editor.view.project(local, rect.size);
            expect(p.x, closeTo(expected.dx, 1e-8));
            expect(p.y, closeTo(expected.dy, 1e-8));
          }
        }

        checkAlignment();
        await tester.tap(find.byKey(const Key('tool-line')));
        await tester.pump();
        for (final point in [Vector2(-20, -10), Vector2(20, -10)]) {
          await tester.tapAt(
            rect.topLeft + editor.view.project(point, rect.size),
          );
          await tester.pump();
        }
        expect(editor.definition!.segments, hasLength(1));
        final pointer = await tester.startGesture(
          rect.center,
          kind: PointerDeviceKind.mouse,
          buttons: kMiddleMouseButton,
        );
        await pointer.moveBy(const Offset(25, -18));
        await pointer.up();
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: rect.center,
            scrollDelta: const Offset(0, -100),
          ),
        );
        await tester.pump();
        expect(editor.view.center, isNot(Offset.zero));
        expect(editor.view.scale, greaterThan(2.5));
        checkAlignment();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sketch face picking overrides measurement inspection', (
    tester,
  ) async {
    final cube = FeatureId('cube');
    final document = DocumentController(
      evaluators: {
        CubeFeature.type: CubeFeature.evaluate,
        SketchFeature.type: SketchFeature.evaluate,
      },
      features: [
        FeatureDefinition(
          id: cube,
          type: CubeFeature.type,
          parameters: {'x': 15, 'y': 16, 'z': 19, 'size': 20},
        ),
      ],
    );
    addTearDown(document.dispose);
    await tester.pumpWidget(MaterialApp(home: CadScreen(controller: document)));
    expect(
      tester.widget<CadScene>(find.byType(CadScene)).selectionMode,
      ViewportSelectionMode.inspect,
    );
    await tester.tap(find.byKey(const Key('start-sketch')));
    await tester.pump();
    final scene = find.byType(CadScene);
    final rect = tester.getRect(scene);
    final projection = CameraProjection(
      tester.widget<CadScene>(scene).cameraConfig,
    );
    final point = projection.project(
      projection.toCameraSpace(Vector3(15, 16, 29)),
      screen: rect.size,
    );
    await tester.tapAt(rect.topLeft + Offset(point.x, point.y));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<SketchWorkspace>(find.byType(SketchWorkspace))
        .editor;
    expect(editor.definition!.support.reference!.featureId, cube);
    expect(
      tester.widget<CadScene>(scene).evaluatedGeometry!.geometry,
      isNotEmpty,
    );
  });
}
