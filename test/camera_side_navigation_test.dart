import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/camera_side.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube.dart';
import 'package:faust_cad_app_2/main_app.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'side navigation includes distant document bodies beyond the grid',
    (tester) async {
      final document = DocumentController(
        evaluators: {CubeFeature.type: CubeFeature.evaluate},
        features: [
          FeatureDefinition(
            id: FeatureId('near'),
            type: CubeFeature.type,
            parameters: {'x': -2500, 'y': 5000, 'z': -1000, 'size': 80},
          ),
          FeatureDefinition(
            id: FeatureId('far'),
            type: CubeFeature.type,
            parameters: {'x': 10000, 'y': -9000, 'z': 15000, 'size': 200},
          ),
        ],
      );
      addTearDown(document.dispose);
      final scene = SceneTessellator().buildGeometry(
        document.evaluation.geometry,
      );
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      await tester.pump();
      for (final side in CameraSide.values) {
        tester.widget<ViewCube>(find.byType(ViewCube)).onSelected(side);
        await tester.pumpAndSettle();
        final projection = CameraProjection(camera(tester));
        for (final edge in scene.edges) {
          for (final point in edge.points) {
            expect(projection.toCameraSpace(point).y, greaterThan(1));
          }
        }
      }
    },
  );

  testWidgets(
    'side transitions animate, stay parallel for pan/zoom, and restore perspective on rotation',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      await tester.pump();
      final initial = camera(tester);
      final cube = find.byType(ViewCube);
      expect(
        tester.getTopRight(cube).dx,
        closeTo(tester.getTopRight(find.byType(CadScene)).dx - 12, 1e-9),
      );
      // The first transition is driven by an actual visible face click.
      final cubeRect = tester.getRect(cube);
      final top =
          cubeRect.topLeft +
          Offset(cubeRect.width * 0.5, cubeRect.height * 0.26);
      await tester.tapAt(top);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      expect(camera(tester).pitch, isNot(initial.pitch));
      expect(camera(tester).isOrthographic, isFalse);
      await tester.pumpAndSettle();
      expect(camera(tester).isOrthographic, isTrue);
      expect(camera(tester).pitch, closeTo(CameraSide.top.pitch, 1e-12));
      for (final side in CameraSide.values) {
        tester.widget<ViewCube>(cube).onSelected(side);
        await tester.pumpAndSettle();
        expect(camera(tester).pitch, side.pitch);
        expect(camera(tester).isOrthographic, isTrue);
        expect(camera(tester).focusDistance, initial.focusDistance);
      }
      final position = tester.getCenter(find.byType(CadScene));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: position),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          panDelta: const Offset(10, 5),
          scale: 1.5,
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(camera(tester).isOrthographic, isTrue);
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(position: position, scale: 1.5),
      );
      await tester.pump();
      expect(camera(tester).isOrthographic, isTrue);
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          panDelta: const Offset(10, 5),
          scale: 1.5,
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: position),
      );
      await tester.pump();
      expect(camera(tester).isOrthographic, isFalse);
    },
  );

  testWidgets(
    'rotation interrupts side animation and reset restores perspective',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      await tester.pump();
      final initial = camera(tester);
      tester
          .widget<ViewCube>(find.byType(ViewCube))
          .onSelected(CameraSide.right);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final position = tester.getCenter(find.byType(CadScene));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: position,
          panDelta: const Offset(10, 5),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: position),
      );
      await tester.pump();
      final interrupted = camera(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(camera(tester), interrupted);
      tester
          .widget<ViewCube>(find.byType(ViewCube))
          .onSelected(CameraSide.back);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(camera(tester).isOrthographic, isFalse);
      expect(camera(tester), initial);
    },
  );
}

CameraConfig camera(WidgetTester tester) =>
    tester.widget<CadScene>(find.byType(CadScene)).cameraConfig;
