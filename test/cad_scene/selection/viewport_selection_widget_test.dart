import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';

import '../../support/attachment_fixtures.dart';

void main() {
  testWidgets(
    'viewport click emits named face, highlights it, and clears on empty space',
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
      final revision = document.evaluation.revision;
      final camera = CameraConfig(
        position: Vertex(Vector3(0, 0, 20)),
        yaw: 0,
        pitch: -math.pi / 2,
        focalLength: 200,
        focusDistance: 20,
      );
      OutputReference? selected;
      ViewportHit? hit;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: StatefulBuilder(
                builder: (context, setState) => CadScene(
                  cameraConfig: camera,
                  evaluatedGeometry: geometry,
                  renderMode: CadRenderMode.shaded,
                  selectedReference: selected,
                  onSelected: (value) => setState(() {
                    hit = value;
                    selected = value?.faceReference;
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      final viewport = tester.getRect(find.byType(CadScene));
      await tester.tapAt(viewport.center);
      await tester.pump();
      expect(hit!.faceReference!.key, 'top');
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(CadScene),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as CadScenePainter;
      expect(painter.selectedFaces, contains(hit!.face));
      expect(document.evaluation.revision, revision);
      await tester.tapAt(viewport.topLeft + const Offset(5, 5));
      await tester.pump();
      expect(hit, isNull);
      expect(selected, isNull);
    },
  );

  testWidgets(
    'existing viewer exposes face reference and resolved local plane',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CadScreen()));
      final finder = find.byType(CadScene);
      final widget = tester.widget<CadScene>(finder);
      final viewport = tester.getRect(finder);
      final projection = CameraProjection(widget.cameraConfig);
      final point = projection.project(
        projection.toCameraSpace(Vector3(15, 16, 29)),
        screen: viewport.size,
      );
      final local = Offset(point.x, point.y);
      final hit =
          ViewportPicker(
            evaluated: widget.evaluatedGeometry!,
            extraGeometry: widget.geometry!,
          ).pick(
            camera: widget.cameraConfig,
            viewport: viewport.size,
            position: local,
          );
      expect(hit?.faceReference, isNotNull);
      await tester.tapAt(viewport.topLeft + local);
      await tester.pump();
      expect(find.text('Resolved plane'), findsOneWidget);
      expect(
        find.text('${hit!.faceReference!.featureId}/${hit.faceReference!.key}'),
        findsOneWidget,
      );
      expect(find.textContaining('Origin:'), findsOneWidget);
      expect(find.textContaining('Normal:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'selected planar fill obeys holes and foreground visibility clipping',
    () async {
      final camera = CameraConfig(
        position: Vertex(Vector3(0, 0, 20)),
        yaw: 0,
        pitch: -math.pi / 2,
        focalLength: 200,
        focusDistance: 20,
      );
      final selected = rectangle(
        PlanarFrame.xy(origin: Vector3(0, 0, 5)),
        hole: true,
      );
      final foreground = rectangle(PlanarFrame.xy(origin: Vector3(4, 0, 8)));
      final background = rectangle(PlanarFrame.xy());
      final scene = SceneTessellator().buildGeometry([
        selected,
        foreground,
        background,
      ], preserveSourceIdentity: true);
      final painter = CadScenePainter(
        cameraConfig: camera,
        evaluatedScene: scene,
        renderMode: CadRenderMode.shaded,
        selectedFaces: {selected},
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(400, 400));
      final picture = recorder.endRecording();
      final image = await picture.toImage(400, 400);
      final data = (await image.toByteData())!;
      List<int> pixel(Vector3 world) {
        final projection = CameraProjection(camera);
        final point = projection.project(
          projection.toCameraSpace(world),
          screen: const Size(400, 400),
        );
        final offset = (point.y.floor() * 400 + point.x.floor()) * 4;
        return [for (var i = 0; i < 3; i++) data.getUint8(offset + i)];
      }

      final visible = pixel(Vector3(-2, 0, 5));
      expect(visible[2], greaterThan(visible[0] + 50));
      final hole = pixel(Vector3(-0.5, 0, 0));
      expect((hole[0] - hole[2]).abs(), lessThan(3));
      final occluded = pixel(Vector3(2, 0, 8));
      expect((occluded[0] - occluded[2]).abs(), lessThan(3));
      image.dispose();
      picture.dispose();
    },
  );
}
