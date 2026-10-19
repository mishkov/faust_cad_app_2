import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/selection/selection_badge.dart';
import 'package:faust_cad_app_2/cad_scene/selection/selection_measurement.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';

import '../../support/extrusion_fixtures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

Future<void> clickWorld(WidgetTester tester, Vector3 point) async {
  final scene = find.byType(CadScene);
  final rect = tester.getRect(scene);
  final projection = CameraProjection(
    tester.widget<CadScene>(scene).cameraConfig,
  );
  final projected = projection.project(
    projection.toCameraSpace(point),
    screen: rect.size,
  );
  await tester.tapAt(rect.topLeft + Offset(projected.x, projected.y));
  await tester.pump();
}

CadScenePainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is CustomPaint && widget.painter is CadScenePainter,
              ),
            )
            .painter!
        as CadScenePainter;

void main() {
  testWidgets(
    'edge badge and cyan selection clear on empty clicks, Escape and edits',
    (tester) async {
      final id = FeatureId('cube');
      FeatureDefinition cube(double size) => FeatureDefinition(
        id: id,
        type: CubeFeature.type,
        parameters: {'x': 15, 'y': 16, 'z': 19, 'size': size},
      );
      final document = DocumentController(
        evaluators: {CubeFeature.type: CubeFeature.evaluate},
        features: [cube(20)],
      );
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      final revision = document.evaluation.revision;
      final undoCount = document.undoCount;
      final badge = find.byKey(const Key('selection-badge'));
      expect(badge, findsNothing);
      await clickWorld(tester, Vector3(15, 6, 29));
      expect(find.text('20'), findsOneWidget);
      expect(painter(tester).selectedEdge, isNotNull);
      expect(painter(tester).selectedFaces, isEmpty);
      final selected = painter(tester).selectedEdge;
      final badgeRect = tester.getRect(
        find.byKey(const Key('selection-badge-surface')),
      );
      await tester.tapAt(badgeRect.topLeft + const Offset(4, 4));
      await tester.pump();
      expect(badge, findsOneWidget);
      expect(painter(tester).selectedEdge, same(selected));
      await tester.tap(find.text('Edge'));
      await tester.pump();
      expect(badge, findsOneWidget);
      expect(painter(tester).selectedEdge, same(selected));
      await tester.tap(find.byKey(const ValueKey('selection-number-Length')));
      await tester.pump();
      expect(badge, findsOneWidget);
      expect(painter(tester).selectedEdge, same(selected));
      final sceneFinder = find.byType(CadScene);
      final rect = tester.getRect(sceneFinder);
      final projection = CameraProjection(
        tester.widget<CadScene>(sceneFinder).cameraConfig,
      );
      final point = projection.project(
        projection.toCameraSpace(Vector3(15, 6, 29)),
        screen: rect.size,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(rect.topLeft + Offset(point.x, point.y));
      await tester.pump();
      expect(painter(tester).hoveredFace, isNull);
      await mouse.removePointer();
      expect(document.evaluation.revision, revision);
      expect(document.undoCount, undoCount);
      await tester.tapAt(
        tester.getRect(find.byType(CadScene)).topRight +
            const Offset(-100, 100),
      );
      await tester.pump();
      expect(badge, findsNothing);
      expect(painter(tester).selectedEdge, isNull);
      await clickWorld(tester, Vector3(15, 6, 29));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(badge, findsNothing);
      await clickWorld(tester, Vector3(15, 6, 29));
      document.setFeature(cube(30));
      await tester.pump();
      expect(badge, findsNothing);
      expect(painter(tester).selectedEdge, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unnamed cylinder shows dimensions and highlights all wall patches',
    (tester) async {
      final document = DocumentController(
        evaluators: {
          'cylinder': (_, _) => [
            FeatureOutput(
              key: 'body',
              kind: OutputKind.body,
              geometry: Cylinder(
                frame: PlanarFrame.xy(origin: Vector3(15, 16, 9)),
                radius: 10,
                height: 20,
              ).build().single,
            ),
          ],
        },
        features: [
          FeatureDefinition(id: FeatureId('cylinder'), type: 'cylinder'),
        ],
      );
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      final undoCount = document.undoCount;
      await clickWorld(tester, Vector3(15, 6, 19));
      expect(find.text('Cylinder'), findsOneWidget);
      expect(find.text('Radius '), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.textContaining('Diameter'), findsNothing);
      expect(find.text('Height '), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(painter(tester).selectedFaces, hasLength(4));
      expect(painter(tester).selectedEdge, isNull);
      expect(document.undoCount, undoCount);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'either half of an extruded rim displays the same complete circle',
    (tester) async {
      final regions = profileArrangement([profileCircle('circle', 0, 0, 10)]);
      final solid = const AnalyticExtrusionService()
          .extrude(
            regions: regions,
            regionIds: regions.regions.map((region) => region.id),
            frame: PlanarFrame.xy(origin: Vector3(15, 16, 9)),
            distance: 20,
          )
          .solids
          .single;
      final document = DocumentController(
        evaluators: {
          'cylinder': (_, _) => [
            FeatureOutput(key: 'body', kind: OutputKind.body, geometry: solid),
          ],
        },
        features: [
          FeatureDefinition(id: FeatureId('cylinder'), type: 'cylinder'),
        ],
      );
      addTearDown(document.dispose);
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      final revision = document.evaluation.revision;
      final undoCount = document.undoCount;
      await clickWorld(tester, Vector3(15, 6, 29));
      final first = painter(tester).selectedEdge;
      expect(first, isNotNull);
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('62.832'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(painter(tester).scene.selectionEdges(first!), hasLength(2));
      await clickWorld(tester, Vector3(15, 26, 29));
      expect(painter(tester).selectedEdge, isNot(same(first)));
      expect(find.text('Circle'), findsOneWidget);
      expect(find.text('62.832'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(document.evaluation.revision, revision);
      expect(document.undoCount, undoCount);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('badge wraps within narrow views and large text, $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const Center(
                child: SizedBox(
                  width: 240,
                  child: SelectionBadge(
                    measurement: SelectionMeasurement('Hole', [
                      (label: 'Radius', value: 0.125),
                      (label: 'Height', value: 5),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('0.125'), findsOneWidget);
      expect(find.textContaining('Diameter'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
