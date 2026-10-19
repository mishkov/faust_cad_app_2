import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

CadScenePainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is CadScenePainter,
              ),
            )
            .painter!
        as CadScenePainter;

void main() {
  testWidgets('hover also targets curved faces without document references', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CadScene(
                cameraConfig: CameraConfig(
                  position: Vertex(Vector3(0, -20, 3)),
                  yaw: 0,
                  pitch: 0,
                  focalLength: 200,
                  focusDistance: 20,
                ),
                cadObjects: [
                  Cylinder(frame: PlanarFrame.xy(), radius: 3, height: 6),
                ],
                backend: CadRenderBackend.canvas,
                renderMode: CadRenderMode.shaded,
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(CadScene)));
    await tester.pump();
    expect(painter(tester).hoveredFace!.surface, isA<CylinderSurface>());
    await mouse.removePointer();
  });

  testWidgets(
    'hover is transient, preserves selection, and follows camera changes',
    (tester) async {
      final document = CadDocument(
        evaluators: {CubeFeature.type: CubeFeature.evaluate},
        features: [
          FeatureDefinition(
            id: FeatureId('cube'),
            type: CubeFeature.type,
            parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 6},
          ),
        ],
      );
      final geometry = document.evaluation.materializeGeometry();
      var camera = CameraConfig(
        position: Vertex(Vector3(0, 0, 20)),
        yaw: 0,
        pitch: -math.pi / 2,
        focalLength: 200,
        focusDistance: 20,
      );
      OutputReference? selected;
      var selections = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return CadScene(
                      cameraConfig: camera,
                      evaluatedGeometry: geometry,
                      backend: CadRenderBackend.canvas,
                      renderMode: CadRenderMode.shaded,
                      selectedReference: selected,
                      onSelected: (hit) => setState(() {
                        selections++;
                        selected = hit?.faceReference;
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(CadScene));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: rect.topLeft + const Offset(10, 10));
      await mouse.moveTo(rect.center);
      await tester.pump();
      expect(painter(tester).hoveredFace, isNotNull);
      final hovered = painter(tester).hoveredFace!;
      expect(geometry.faces[hovered]!.key, 'top');
      expect(selections, 0);
      await tester.tapAt(rect.center);
      await tester.pump();
      expect(selections, 1);
      expect(painter(tester).selectedFaces, contains(hovered));
      await mouse.moveTo(rect.topLeft + const Offset(10, 10));
      await tester.pump();
      expect(painter(tester).hoveredFace, isNull);
      expect(painter(tester).selectedFaces, contains(hovered));
      await mouse.moveTo(rect.center);
      await tester.pump();
      expect(painter(tester).hoveredFace, hovered);
      rebuild(() => camera = camera.pan(const Offset(500, 0)));
      await tester.pump();
      expect(painter(tester).hoveredFace, isNull);
      rebuild(() => camera = camera.pan(const Offset(-500, 0)));
      await tester.pump();
      expect(painter(tester).hoveredFace, hovered);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(painter(tester).hoveredFace, isNull);
      expect(document.evaluation.revision, 1);
      await mouse.removePointer();
    },
  );
}
