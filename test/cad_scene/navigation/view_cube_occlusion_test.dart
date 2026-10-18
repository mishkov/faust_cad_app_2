import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube.dart';
import 'package:faust_cad_app_2/cad_scene/navigation/view_cube_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  for (final front in [true, false]) {
    testWidgets(
      front
          ? 'foreground axis remains visible over cube faces'
          : 'rear axis stays hidden by cube faces',
      (tester) async {
        final camera = CameraConfig(
          position: Vertex(Vector3.zero()),
          yaw: front ? -.3 : math.pi - .3,
          pitch: front ? -.5 : .5,
          focalLength: 500,
          focusDistance: 200,
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(),
            home: Center(
              child: RepaintBoundary(
                key: key,
                child: ViewCube(camera: camera, onSelected: (_) {}),
              ),
            ),
          ),
        );
        await tester.pump();
        final geometry = ViewCubeGeometry(
          camera,
          tester.getSize(find.byType(ViewCube)),
        );
        final candidates = [
          for (var i = 0; i <= 100; i++)
            geometry.project(Vector3(-1.25, -1.25, -.9 + i * .02)),
        ];
        // Find an interior overlap, away from antialiased face boundaries.
        final sample = candidates.firstWhere(
          (p) => geometry.visibleSides.any(
            (side) => [
              const Offset(-2, 0),
              const Offset(2, 0),
              const Offset(0, -2),
              const Offset(0, 2),
            ].every((delta) => geometry.path(side).contains(p + delta)),
          ),
        );
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 4);
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final offset =
                ((sample.dy * 4).floor() * image.width +
                    (sample.dx * 4).floor()) *
                4;
            const blue = [0x27, 0x69, 0xA5];
            final isAxisBlue = [0, 1, 2].every(
              (channel) =>
                  (data.getUint8(offset + channel) - blue[channel]).abs() < 30,
            );
            expect(isAxisBlue, front);
          } finally {
            image.dispose();
          }
        });
      },
    );
  }

  test('label masks respect depth instead of always hiding inside the cube outline', () {
    final camera = CameraConfig(
      position: Vertex(Vector3.zero()),
      yaw: 0,
      pitch: 0,
      focalLength: 500,
      focusDistance: 200,
    );
    final geometry = ViewCubeGeometry(camera, const Size(132, 132));
    final center = geometry.project(Vector3.zero());
    expect(geometry.occlusionPath(Vector3(0, -2, 0)).contains(center), isFalse);
    expect(geometry.occlusionPath(Vector3(0, 2, 0)).contains(center), isTrue);
  });
}
