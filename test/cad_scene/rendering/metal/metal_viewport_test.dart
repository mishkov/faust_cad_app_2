import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  testWidgets(
    'unsupported Metal shows an error without constructing a Canvas scene',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CadScene(
              backend: CadRenderBackend.metal,
              cameraConfig: CameraConfig(
                position: Vertex(Vector3(0, -10, 10)),
                yaw: 0,
                pitch: 0,
                focalLength: 500,
                focusDistance: 10,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('metal-error')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is CadScenePainter,
        ),
        findsNothing,
      );
    },
  );
}
