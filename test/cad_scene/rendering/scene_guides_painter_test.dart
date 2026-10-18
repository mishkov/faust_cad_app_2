import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/scene_guides_painter.dart';

void main() {
  for (final orthographic in [false, true]) {
    test(
      'positive RGB axes remain long in ${orthographic ? 'parallel' : 'perspective'} view',
      () {
        final camera = CameraConfig(
          position: Vertex(Vector3(110, -160, 120)),
          yaw: 0.6,
          pitch: -0.55,
          focalLength: 500,
          focusDistance: 200,
          isOrthographic: orthographic,
        );
        const size = Size(700, 550);
        final origin = CameraProjection(camera).project(
          CameraProjection(camera).toCameraSpace(Vector3.zero()),
          screen: size,
        );
        void paint(Canvas canvas) =>
            SceneGuidesPainter(camera: camera).paint(canvas, size);
        expect(paint, paintsExactlyCountTimes(#drawLine, 3));
        expect(
          paint,
          paints
            ..line(
              p1: Offset(origin.x, origin.y),
              color: const Color(0xffc34d52),
            )
            ..line(
              p1: Offset(origin.x, origin.y),
              color: const Color(0xff43a568),
            )
            ..line(
              p1: Offset(origin.x, origin.y),
              color: const Color(0xff4489cc),
            ),
        );
        expect(
          paint,
          paints..everything((method, arguments) {
            if (method != #drawLine) return true;
            final end = arguments[1] as Offset;
            expect(
              end.dx == 0 ||
                  end.dx == size.width ||
                  end.dy == 0 ||
                  end.dy == size.height,
              isTrue,
            );
            return true;
          }),
        );
      },
    );
  }
}
