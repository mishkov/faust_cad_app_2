import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/scene_guides_painter.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';

import '../../support/attachment_fixtures.dart';

void main() {
  for (final orthographic in [false, true]) {
    for (final testCase in [
      (
        name: 'foreground material hides the axis',
        front: true,
        hole: false,
        visible: false,
      ),
      (
        name: 'a hole preserves the axis behind it',
        front: true,
        hole: true,
        visible: true,
      ),
      (
        name: 'material behind the axis leaves it visible',
        front: false,
        hole: false,
        visible: true,
      ),
    ]) {
      test(
        '${testCase.name} in ${orthographic ? 'parallel' : 'perspective'} view',
        () async {
          final eye = Vector3(0, -20, 15);
          final camera = CameraConfig(
            position: Vertex(eye),
            yaw: 0,
            pitch: -math.atan2(15, 20),
            focalLength: 400,
            focusDistance: 25,
            isOrthographic: orthographic,
          );
          final projection = CameraProjection(camera);
          final point = Vector3(5, 0, 0);
          final outward = projection.fromCameraDirection(Vector3(0, -1, 0));
          final center = orthographic
              ? point + outward * (testCase.front ? 5 : -5)
              : eye + (point - eye) * (testCase.front ? 0.8 : 1.2);
          final support = PlanarFrame(
            origin: center,
            xAxis: Vector3(1, 0, 0),
            yAxis: projection.fromCameraDirection(Vector3(0, 0, 1)),
          );
          final scene = SceneTessellator().buildGeometry([
            rectangle(support, hole: testCase.hole),
          ]);
          final recorder = ui.PictureRecorder();
          SceneGuidesPainter(
            camera: camera,
            occluders: scene,
          ).paint(Canvas(recorder), const Size(400, 400));
          final picture = recorder.endRecording();
          final image = await picture.toImage(400, 400);
          final bytes = (await image.toByteData())!;
          final screen = projection.project(
            projection.toCameraSpace(point),
            screen: const Size(400, 400),
          );
          var alpha = 0;
          for (var y = screen.y.floor() - 1; y <= screen.y.ceil() + 1; y++) {
            for (var x = screen.x.floor() - 1; x <= screen.x.ceil() + 1; x++) {
              alpha = math.max(alpha, bytes.getUint8((y * 400 + x) * 4 + 3));
            }
          }
          expect(alpha, testCase.visible ? greaterThan(0) : 0);
          image.dispose();
          picture.dispose();
        },
      );
    }
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
