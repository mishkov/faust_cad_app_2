import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/gpu/gpu_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../test/support/orbit_extrusion_fixture.dart';
import 'support/gpu_image_comparison.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Canvas/GPU quality matrix records strict diagnostic gates',
    (tester) async {
      binding.reportData = {
        'gpu_image_comparisons': await tester.runAsync(compareGpuImages),
      };
    },
  );
  testWidgets('bounded camera uploads and working Material controls', (
    tester,
  ) async {
    final geometry = orbitGeometry(orbitSketch());
    final scene = SceneTessellator().buildGeometry(geometry);
    final renderer = await tester.runAsync(GpuSceneRenderer.create);
    final camera = CameraConfig(
      position: Vertex(Vector3(0, -200, 100)),
      yaw: 0,
      pitch: -0.5,
      focalLength: 500,
      focusDistance: 220,
    );
    await tester.runAsync(() async {
      for (final (size, dpr) in [
        (const ui.Size(640, 480), 1.0),
        (const ui.Size(743, 696), 2.0),
        (const ui.Size(640, 480), 1.0),
      ]) {
        final image = renderer!.render(camera, size, dpr, scene);
        await renderer.completed;
        image?.dispose();
      }
      expect(renderer!.targetRecreations, 3);
      final selected = renderer.render(
        camera,
        const ui.Size(640, 480),
        1,
        scene,
        selected: {scene.faces.first.source},
      );
      await renderer.completed;
      selected?.dispose();
      for (var i = 0; i < 32 && renderer.failure == null; i++) {
        try {
          final image = renderer.render(
            camera.pan(Offset(i.toDouble(), 0)),
            const ui.Size(640, 480),
            1,
            scene,
          );
          await renderer.completed;
          image?.dispose();
        } on StateError {
          if (renderer.failure == null) rethrow;
        }
      }
      expect(renderer.maximumBackingTextures, lessThanOrEqualTo(8));
      expect(renderer.geometryUploads, 1);
      expect(renderer.completions, renderer.submissions);
      final report = binding.reportData ?? {};
      report['gpu_resource_probe'] = {
        'submissions': renderer.submissions,
        'completions': renderer.completions,
        'geometry_uploads': renderer.geometryUploads,
        'maximum_backing_textures': renderer.maximumBackingTextures,
        'budget_stops': renderer.resourceBudgetStops,
        'target_recreations': renderer.targetRecreations,
        'failure': '${renderer.failure}',
      };
      binding.reportData = report;
      renderer.dispose();
      final inFlight = await GpuSceneRenderer.create();
      final original = inFlight.render(
        camera,
        const ui.Size(320, 240),
        1,
        scene,
      );
      expect(
        inFlight.render(
          camera.pan(const Offset(1, 0)),
          const ui.Size(320, 240),
          1,
          scene,
        ),
        isNull,
      );
      expect(inFlight.busyPaints, 1);
      await inFlight.completed;
      original?.dispose();
      final originalBytes = inFlight.uploadedGeometryBytes;
      final revised = SceneTessellator().buildGeometry(
        geometry.sublist(0, geometry.length - 1),
        geometryRevision: 2,
      );
      final image = inFlight.render(
        camera,
        const ui.Size(320, 240),
        1,
        revised,
      );
      expect(inFlight.geometryUploads, 2);
      expect(inFlight.uploadedGeometryBytes, lessThan(originalBytes));
      final done = inFlight.completed;
      inFlight.dispose();
      await done;
      image?.dispose();
    });
    final step = ValueNotifier<int>(0);
    addTearDown(step.dispose);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 240,
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: () => taps++,
                      child: const Text('Control'),
                    ),
                    const TextField(),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: step,
                  builder: (context, value, child) => CadScene(
                    cameraConfig: camera.pan(Offset(value.toDouble(), 0)),
                    geometry: geometry,
                    renderMode: CadRenderMode.shaded,
                    backend: CadRenderBackend.flutterGpu,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      step.value = i;
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Control'));
    expect(taps, 1);
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    await tester.enterText(find.byType(TextField), '12');
    expect(find.text('12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'GPU bodies and CAD strokes render without CPU readback presentation',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await GpuSceneRenderer.create();
        final scene = SceneTessellator().buildGeometry(
          orbitGeometry(orbitSketch()),
        );
        final yaw = -0.95, pitch = -0.5;
        final forward = Vector3(
          -math.sin(yaw) * math.cos(pitch),
          math.cos(yaw) * math.cos(pitch),
          math.sin(pitch),
        );
        final camera = CameraConfig(
          position: Vertex(Vector3(35, 25, 5) - forward * 220),
          yaw: yaw,
          pitch: pitch,
          focalLength: 500,
          focusDistance: 220,
        );
        final image = renderer.render(
          camera,
          const ui.Size(743, 696),
          1,
          scene,
        )!;
        await renderer.completed;
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        expect(
          bytes.getUint8(3),
          0,
          reason: 'Viewport background must remain transparent',
        );
        var gray = 0, black = 0, red = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          final r = bytes.getUint8(i),
              g = bytes.getUint8(i + 1),
              b = bytes.getUint8(i + 2);
          if (r > 40 && r < 220 && (r - g).abs() < 3 && (r - b).abs() < 3) {
            gray++;
          }
          if (r < 40 && g < 40 && b < 40 && bytes.getUint8(i + 3) == 255) {
            black++;
          }
          if (r > 200 && g < 100 && b < 100) red++;
        }
        expect(gray, greaterThan(1000));
        expect(black, greaterThan(100));
        expect(red, greaterThan(100));
        image.dispose();
        renderer.dispose();
      });
    },
  );
}
