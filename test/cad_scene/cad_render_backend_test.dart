import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MetalViewportController.channel, (_) async {
          throw PlatformException(code: 'metal-unavailable');
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MetalViewportController.channel, null);
  });
  const override = String.fromEnvironment('CAD_RENDER_BACKEND');
  final camera = CameraConfig(
    position: Vertex(Vector3(0, -10, 10)),
    yaw: 0,
    pitch: 0,
    focalLength: 500,
    focusDistance: 10,
  );
  final canvas = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is CadScenePainter,
  );

  for (final platform in TargetPlatform.values) {
    final expected = override == 'canvas'
        ? CadRenderBackend.canvas
        : override == 'metal'
        ? CadRenderBackend.metal
        : platform == TargetPlatform.macOS && !kIsWeb
        ? CadRenderBackend.metal
        : CadRenderBackend.canvas;
    testWidgets(
      'unconfigured scene uses ${expected.name} on ${platform.name}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: CadScene(cameraConfig: camera)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(MetalViewport),
          expected == CadRenderBackend.metal ? findsOneWidget : findsNothing,
        );
        expect(
          canvas,
          expected == CadRenderBackend.canvas ? findsOneWidget : findsNothing,
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('explicit Canvas overrides the macOS default and build setting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CadScene(cameraConfig: camera, backend: CadRenderBackend.canvas),
      ),
    );
    expect(canvas, findsOneWidget);
    expect(find.byType(MetalViewport), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
