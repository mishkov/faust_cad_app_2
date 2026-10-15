import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_sketch_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/shaded_scene_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/sketch_editor/presentation/sketch_scene_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../test/support/orbit_extrusion_fixture.dart';

Future<Map<String, dynamic>> validateMetalImages(
  MetalViewportController controller,
) async {
  final results = <Map<String, dynamic>>[], images = <String, String>{};
  final sketch = orbitSketch(), geometry = orbitGeometry(orbitSketch());
  final views = [
    (-.95, -.5),
    (-1.2, -.05),
    (-.7, .09),
    (0.0, 0.0),
    (.7, .3),
    (-.95, .8),
    (-.95, 1.2),
    (1.8, -.7),
    (2.8, .5),
  ];
  for (final scenario in [
    'default',
    'partial',
    'inside',
    'near',
    'selection',
    'holes',
    'cavity',
    'reverse',
    'wireframe',
  ]) {
    final hasSketch = scenario == 'partial' || scenario == 'wireframe';
    final scene = SceneTessellator().buildGeometry(
      scenario == 'holes'
          ? Tube(
              frame: PlanarFrame.xy(origin: Vector3(35, 25, 0)),
              outerRadius: 24,
              innerRadius: 14,
              height: 30,
            ).build()
          : scenario == 'cavity'
          ? [
              Solid(
                shells: [
                  Cube(
                    centerPosition: Vertex(Vector3.zero()),
                    size: 40,
                  ).build().single.shells.single,
                  Shell(
                    faces:
                        Cube(centerPosition: Vertex(Vector3.zero()), size: 20)
                            .build()
                            .single
                            .shells
                            .single
                            .faces
                            .map((f) => f.reversed())
                            .toList(),
                  ),
                ],
              ),
            ]
          : scenario == 'reverse'
          ? geometry.reversed.toList()
          : scenario == 'default'
          ? geometry.sublist(0, geometry.length - 1)
          : scenario == 'inside' || scenario == 'near'
          ? Cube(centerPosition: Vertex(Vector3.zero()), size: 20).build()
          : geometry,
    );
    final mesh = MetalSceneMesh(scene);
    final cameras = <CameraConfig>[
      if (scenario == 'inside' || scenario == 'near' || scenario == 'cavity')
        CameraConfig(
          position: Vertex(Vector3(0, scenario == 'near' ? -10.000001 : 0, 0)),
          yaw: .2,
          pitch: .12,
          focalLength: 500,
          focusDistance: 20,
        )
      else
        for (final (yaw, pitch) in views)
          CameraConfig(
            position: Vertex(
              Vector3(35, 25, 5) -
                  Vector3(
                        -math.sin(yaw) * math.cos(pitch),
                        math.cos(yaw) * math.cos(pitch),
                        math.sin(pitch),
                      ) *
                      220,
            ),
            yaw: yaw,
            pitch: pitch,
            focalLength: 500,
            focusDistance: 220,
          ),
    ];
    for (var angle = 0; angle < cameras.length; angle++) {
      final camera = cameras[angle], p = camera.position.vector;
      for (final dpr in [1.0, 1.5, 2.0]) {
        final size = angle.isEven ? const Size(743, 696) : const Size(640, 480);
        final selected = scenario == 'selection'
            ? mesh.faces.take(2).toSet()
            : mesh.faces.take(0).toSet();
        controller.update({
          'mesh': mesh.message,
          'sketches': hasSketch
              ? [MetalSketchMesh(sketch).message]
              : <Object>[],
          'camera': Float64List.fromList([
            p.x,
            p.y,
            p.z,
            camera.yaw,
            camera.pitch,
            camera.focalLength,
            size.width,
            size.height,
            dpr,
          ]),
          'selection': mesh.selection(selected),
          'wireframe': scenario == 'wireframe',
          'clear': Float64List.fromList([1, 1, 1, 1]),
        });
        final captured = await controller.capture();
        final w = captured['width'] as int, h = captured['height'] as int;
        final bgra = captured['bgra'] as Uint8List;
        final recorder = ui.PictureRecorder(),
            canvas = Canvas(recorder)..scale(dpr);
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
        if (scenario == 'wireframe') {
          CadScenePainter(
            cameraConfig: camera,
            evaluatedScene: scene,
          ).paint(canvas, size);
        } else {
          ShadedSceneRenderer(
            camera,
            devicePixelRatio: dpr,
          ).paint(canvas, size, scene, selectedFaces: selected);
        }
        if (hasSketch) {
          SketchScenePainter(
            sketches: [sketch],
            camera: camera,
            occluders: scene,
          ).paint(canvas, size);
        }
        final picture = recorder.endRecording(),
            reference = await picture.toImage(w, h);
        picture.dispose();
        final rgba = (await reference.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        // Regression for coplanar sketch fill on the extrusion underside.
        // These reference pixels are safely inside one uniformly lit plane.
        if (scenario == 'partial' && angle == 5 && dpr == 1) {
          var expected = 0, covered = 0;
          for (var y = 150; y < 230; y++) {
            for (var x = 220; x < 300; x++) {
              final i = (y * w + x) * 4;
              if (rgba[i] == 77 && rgba[i + 1] == 89 && rgba[i + 2] == 98) {
                expected++;
                if ((rgba[i] - bgra[i + 2]).abs() <= 2 &&
                    (rgba[i + 1] - bgra[i + 1]).abs() <= 2 &&
                    (rgba[i + 2] - bgra[i]).abs() <= 2) {
                  covered++;
                }
              }
            }
          }
          expect(expected, greaterThan(1000));
          expect(
            covered / expected,
            greaterThan(.99),
            reason: 'Coplanar sketch fill must not form depth bands',
          );
        }
        var total = 0,
            over4 = 0,
            maximum = 0,
            interiorOver4 = 0,
            interiorPixels = 0;
        bool isBoundary(int x, int y) {
          final i = (y * w + x) * 4;
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final xx = x + dx, yy = y + dy;
              if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
              final j = (yy * w + xx) * 4;
              for (var c = 0; c < 3; c++) {
                if ((rgba[i + c] - rgba[j + c]).abs() > 10) return true;
              }
            }
          }
          return false;
        }

        for (var i = 0; i < rgba.length; i += 4) {
          var delta = 0;
          for (var c = 0; c < 3; c++) {
            final d = (rgba[i + c] - bgra[i + 2 - c]).abs();
            total += d;
            delta = math.max(delta, d);
          }
          maximum = math.max(maximum, delta);
          if (delta > 4) over4++;
          if (!isBoundary(i ~/ 4 % w, i ~/ 4 ~/ w)) {
            interiorPixels++;
            if (delta > 4) interiorOver4++;
          }
        }
        final result = {
          'scenario': scenario,
          'angle': angle,
          'dpr': dpr,
          'width': w,
          'height': h,
          'meanAbsoluteChannelDelta': total / (w * h * 3),
          'pixelsOver4Percent': over4 / (w * h) * 100,
          'interiorPixelsOver4Percent':
              interiorOver4 / math.max(1, interiorPixels) * 100,
          'maximumDelta': maximum,
        };
        results.add(result);
        if ((angle == 0 || scenario == 'partial' && angle == 5) && dpr == 1) {
          final name = '${scenario}_$angle';
          images['${name}_canvas'] = base64Encode(
            (await reference.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          final decoded = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            bgra,
            w,
            h,
            ui.PixelFormat.bgra8888,
            decoded.complete,
          );
          final image = await decoded.future;
          images['${name}_metal'] = base64Encode(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
          image.dispose();
        }
        reference.dispose();
        // These catch missing/inverted solids and gross projection/lighting errors.
        // Report all exact deltas; antialiasing differences remain visible in results.
        expect(
          result['meanAbsoluteChannelDelta'] as double,
          lessThan(0.65),
          reason: '$result',
        );
      }
    }
  }
  return {'imageComparisons': results, 'images': images};
}
