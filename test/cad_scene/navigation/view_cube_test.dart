import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/camera_side.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube_geometry.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube_painter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  testWidgets(
    'only faces react to hover and clicks; axes and empty space do not',
    (tester) async {
      final camera = CameraConfig(
        position: Vertex(Vector3.zero()),
        yaw: -.6,
        pitch: -.5,
        focalLength: 500,
        focusDistance: 200,
      );
      final selected = <CameraSide>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ViewCube(camera: camera, onSelected: selected.add),
          ),
        ),
      );
      final origin = tester.getTopLeft(find.byType(ViewCube));
      final geometry = ViewCubeGeometry(camera, const Size(132, 132));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final side in geometry.visibleSides) {
        final corners = geometry.corners(side);
        final center = origin + (corners[0] + corners[2]) / 2;
        await mouse.moveTo(center);
        await tester.pump();
        final painters = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(ViewCube),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((w) => w.painter)
            .whereType<ViewCubePainter>();
        expect(painters.where((p) => p.highlighted).single.side, side);
        await tester.tapAt(center);
        expect(selected.last, side);
      }
      await mouse.moveTo(origin);
      await tester.pump();
      final count = selected.length;
      await tester.tapAt(origin + const Offset(2, 2));
      expect(selected.length, count);
      final painters = tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(ViewCube),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((w) => w.painter)
          .whereType<ViewCubePainter>();
      expect(painters.any((p) => p.highlighted), isFalse);
    },
  );
}
