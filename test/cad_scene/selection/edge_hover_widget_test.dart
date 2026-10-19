import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../support/attachment_fixtures.dart';
import '../../support/extrusion_fixtures.dart';

CadScenePainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is CadScenePainter,
              ),
            )
            .painter!
        as CadScenePainter;
Offset screenPoint(WidgetTester tester, Vector3 world) {
  final finder = find.byType(CadScene),
      rect = tester.getRect(find.byType(CadScene));
  final projection = CameraProjection(
    tester.widget<CadScene>(finder).cameraConfig,
  );
  final p = projection.project(
    projection.toCameraSpace(world),
    screen: rect.size,
  );
  return rect.topLeft + Offset(p.x, p.y);
}

final topCamera = CameraConfig(
  position: Vertex(Vector3(0, 0, 20)),
  yaw: 0,
  pitch: -math.pi / 2,
  focalLength: 200,
  focusDistance: 20,
);

void main() {
  testWidgets(
    'hover previews edges without changing the clicked selection and follows camera changes',
    (tester) async {
      final face = rectangle(PlanarFrame.xy(origin: Vector3(0, 0, 5)));
      ViewportHit? selected;
      var selections = 0;
      var camera = topCamera;
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
                      geometry: [face],
                      backend: CadRenderBackend.canvas,
                      renderMode: CadRenderMode.shaded,
                      selectionMode: ViewportSelectionMode.inspect,
                      selectedHit: selected,
                      onSelected: (hit) => setState(() {
                        selected = hit;
                        selections++;
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final firstPoint = screenPoint(tester, Vector3(0, -4, 5));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(firstPoint);
      await tester.pump();
      expect(painter(tester).hoveredEdge, same(face.outerWire.edges.first));
      expect(painter(tester).hoveredFace, isNull);
      expect(painter(tester).selectedEdge, isNull);
      expect(selections, 0);
      await tester.tapAt(firstPoint);
      await tester.pump();
      final clicked = painter(tester).selectedEdge!;
      await mouse.moveTo(screenPoint(tester, Vector3(4, 0, 5)));
      await tester.pump();
      expect(painter(tester).hoveredEdge, same(face.outerWire.edges[1]));
      expect(painter(tester).selectedEdge, same(clicked));
      expect(selections, 1);
      rebuild(() => camera = camera.pan(const Offset(500, 0)));
      await tester.pump();
      expect(painter(tester).hoveredEdge, isNull);
      rebuild(() => camera = camera.pan(const Offset(-500, 0)));
      await tester.pump();
      expect(painter(tester).hoveredEdge, same(face.outerWire.edges[1]));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(painter(tester).hoveredEdge, isNull);
      expect(painter(tester).selectedEdge, same(clicked));
      await mouse.removePointer();
    },
  );

  testWidgets('hovering either circular arc previews the complete rim', (
    tester,
  ) async {
    final regions = profileArrangement([profileCircle('circle', 0, 0, 3)]);
    final solid = const AnalyticExtrusionService()
        .extrude(
          regions: regions,
          regionIds: regions.regions.map((r) => r.id),
          frame: PlanarFrame.xy(),
          distance: 6,
        )
        .solids
        .single;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CadScene(
                cameraConfig: topCamera,
                geometry: [solid],
                backend: CadRenderBackend.canvas,
                renderMode: CadRenderMode.shaded,
                selectionMode: ViewportSelectionMode.inspect,
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      screenPoint(tester, Vector3(3 / math.sqrt(2), 3 / math.sqrt(2), 6)),
    );
    await tester.pump();
    final first = painter(tester).hoveredEdge!;
    final circle = painter(tester).scene.selectionEdges(first);
    expect(circle, hasLength(2));
    await mouse.moveTo(
      screenPoint(tester, Vector3(-3 / math.sqrt(2), -3 / math.sqrt(2), 6)),
    );
    await tester.pump();
    final second = painter(tester).hoveredEdge!;
    expect(second, isNot(same(first)));
    expect(
      painter(tester).scene.selectionEdges(second),
      unorderedEquals(circle),
    );
    expect(painter(tester).selectedEdge, isNull);
    await mouse.removePointer();
  });

  testWidgets('hovering cylinder patches previews the same continuous wall', (
    tester,
  ) async {
    final solid = Cylinder(
      frame: PlanarFrame.xy(),
      radius: 3,
      height: 6,
    ).build().single;
    final camera = CameraConfig(
      position: Vertex(Vector3(0, -20, 3)),
      yaw: 0,
      pitch: 0,
      focalLength: 200,
      focusDistance: 20,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CadScene(
                cameraConfig: camera,
                geometry: [solid],
                backend: CadRenderBackend.canvas,
                renderMode: CadRenderMode.shaded,
                selectionMode: ViewportSelectionMode.inspect,
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(screenPoint(tester, Vector3(1, -math.sqrt(8), 3)));
    await tester.pump();
    final first = painter(tester).hoveredFace!;
    final wall = painter(tester).scene.hoverFaces(first);
    expect(wall, hasLength(4));
    await mouse.moveTo(screenPoint(tester, Vector3(-1, -math.sqrt(8), 3)));
    await tester.pump();
    expect(painter(tester).hoveredFace, isNot(same(first)));
    expect(
      painter(tester).scene.hoverFaces(painter(tester).hoveredFace),
      unorderedEquals(wall),
    );
    expect(painter(tester).hoveredEdge, isNull);
    await mouse.removePointer();
    await tester.pump();
    expect(painter(tester).hoveredFace, isNull);
  });
}
