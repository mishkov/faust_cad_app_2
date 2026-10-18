import 'dart:math' as math;
import 'dart:typed_data';

import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../test/support/attachment_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Metal hover lightens material, outlines the hole, and clears', (
    tester,
  ) async {
    final controller = MetalViewportController();
    final camera = CameraConfig(
      position: Vertex(Vector3(0, 0, 20)),
      yaw: 0,
      pitch: -math.pi / 2,
      focalLength: 200,
      focusDistance: 20,
    );
    final face = rectangle(
      PlanarFrame.xy(origin: Vector3(0, 0, 5)),
      hole: true,
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
                geometry: [face],
                backend: CadRenderBackend.metal,
                renderMode: CadRenderMode.shaded,
                metalController: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await controller.ready, greaterThanOrEqualTo(0));
    expect(controller.error.value, isNull);
    final rect = tester.getRect(find.byType(CadScene));
    final projection = CameraProjection(camera);
    final p = projection.project(
      projection.toCameraSpace(Vector3(-2, 0, 5)),
      screen: rect.size,
    );
    final normal = await controller.capture();
    final uploads = (await controller.stats())['geometryUploads'];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: rect.topLeft + const Offset(5, 5));
    await mouse.moveTo(rect.topLeft + Offset(p.x, p.y));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MetalViewport>(find.byType(MetalViewport)).hoveredFace,
      face,
    );
    final hover = await controller.capture();
    expect((await controller.stats())['geometryUploads'], uploads);
    int red(Map<String, dynamic> capture) {
      final width = capture['width'] as int;
      final dpr = width / rect.width;
      final bytes = capture['bgra'] as Uint8List;
      return bytes[((p.y * dpr).floor() * width + (p.x * dpr).floor()) * 4 + 2];
    }

    int cyan(Map<String, dynamic> capture) {
      final bytes = capture['bgra'] as Uint8List;
      var count = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > bytes[i + 2] + 60 && bytes[i + 1] > bytes[i + 2] + 60) {
          count++;
        }
      }
      return count;
    }

    expect(red(hover), greaterThan(red(normal) + 5));
    expect(cyan(normal), 0);
    expect(cyan(hover), greaterThan(100));
    await mouse.moveTo(rect.topLeft + const Offset(5, 5));
    await tester.pumpAndSettle();
    final cleared = await controller.capture();
    expect(red(cleared), red(normal));
    expect(cyan(cleared), 0);
    expect(controller.error.value, isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });
}
