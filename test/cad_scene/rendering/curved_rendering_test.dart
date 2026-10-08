import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

const size = 240;
final camera = view(Vector3.zero(), Vector3(0, 10, 0), focal: 160);
CameraConfig view(Vector3 eye, Vector3 target, {double focal = 260}) {
  final direction = (target - eye).normalized();
  return CameraConfig(
    position: Vertex(eye),
    yaw: math.atan2(-direction.x, direction.y),
    pitch: math.asin(direction.z),
    focalLength: focal,
    focusDistance: (target - eye).length,
  );
}

Future<Uint8List> render(
  List<CadObject> objects, {
  CameraConfig? cameraConfig,
  CadRenderMode mode = CadRenderMode.shaded,
  String? export,
}) async {
  final recorder = ui.PictureRecorder();
  CadScenePainter(
    cameraConfig: cameraConfig ?? camera,
    cadObjects: objects,
    renderMode: mode,
  ).paint(Canvas(recorder), const Size(240, 240));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final directory = Platform.environment['CURVED_RENDER_OUTPUT'];
  if (export != null && directory != null) {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$export.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

List<int> pixel(Uint8List bytes, int x, int y) =>
    bytes.sublist((y * size + x) * 4, (y * size + x) * 4 + 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('end-on annular caps and through bore reveal rear wires', () async {
    final tube = Tube(
      frame: PlanarFrame.xz(origin: Vector3(0, 12, 0)),
      outerRadius: 3,
      innerRadius: 1.3,
      height: 3,
    );
    final alone = await render([tube], export: 'tube-end');
    expect(pixel(alone, 120, 120)[3], 0);
    expect(pixel(alone, 150, 120)[3], 255);
    final line = Objects([
      Edge(
        Vertex(Vector3(-6, 16, 0)),
        Vertex(Vector3(6, 16, 0)),
        curve: const LinearCadCurve(),
      ),
    ]);
    final combined = await render([tube, line], export: 'tube-hole-wire');
    expect(pixel(combined, 120, 120)[0], greaterThan(100));
    expect(pixel(combined, 120, 120)[1], lessThan(100));
    expect(pixel(combined, 150, 120), pixel(alone, 150, 120));
    expect(await render([line, tube]), orderedEquals(combined));
    final frame = await render(
      [tube],
      mode: CadRenderMode.frame,
      export: 'tube-frame-end',
    );
    expect(pixel(frame, 150, 120)[3], 0);
    expect(frame.where((v) => v > 0), isNotEmpty);
  });

  test(
    'cylinder side is opaque, smoothly lit, and free of patch seam outlines',
    () async {
      final cylinder = Cylinder(
        frame: PlanarFrame.xy(origin: Vector3(0, 10, -3)),
        radius: 3,
        height: 6,
      );
      final image = await render([cylinder], export: 'cylinder-side');
      final brightness = [
        for (var x = 100; x <= 140; x++) pixel(image, x, 120)[0],
      ];
      for (var x = 90; x <= 150; x++) {
        expect(
          pixel(image, x, 120)[3],
          255,
          reason: 'Internal cell crack at x=$x',
        );
        expect(
          pixel(image, x, 120)[0],
          greaterThan(50),
          reason: 'Patch seam at x=$x',
        );
      }
      expect(brightness.toSet().length, greaterThan(15));
      for (var i = 1; i < brightness.length; i++) {
        expect((brightness[i] - brightness[i - 1]).abs(), lessThan(10));
      }
      final rear = Objects([
        Wire.circular(
          CircularCadCurve(
            frame: PlanarFrame.xz(origin: Vector3(0, 16, 0)),
            radius: 1,
          ),
        ),
      ]);
      expect(await render([cylinder, rear]), orderedEquals(image));
      final frame = await render(
        [cylinder],
        mode: CadRenderMode.frame,
        export: 'cylinder-frame-side',
      );
      expect(pixel(frame, 120, 120)[3], 0);
    },
  );

  test(
    'existing cube occludes curved faces and wires independent of order',
    () async {
      final cube = Cube(centerPosition: Vertex(Vector3(0, 6, 0)), size: 6);
      final behind = Tube(
        frame: PlanarFrame.xy(origin: Vector3(0, 14, -2)),
        outerRadius: 2,
        innerRadius: 1,
        height: 4,
      );
      final alone = await render([cube]);
      expect(await render([cube, behind]), orderedEquals(alone));
      expect(await render([behind, cube]), orderedEquals(alone));
    },
  );

  test('tilted cylinder and camera preserve analytic lighting', () async {
    const yaw = 0.7, pitch = -0.4;
    final translation = Vector3(2, -3, 1);
    Vector3 rotate(Vector3 p) {
      final y = p.y * math.cos(pitch) - p.z * math.sin(pitch);
      final z = p.y * math.sin(pitch) + p.z * math.cos(pitch);
      return Vector3(
        p.x * math.cos(yaw) - y * math.sin(yaw),
        p.x * math.sin(yaw) + y * math.cos(yaw),
        z,
      );
    }

    final cylinder = Cylinder(
      frame: PlanarFrame.xy(origin: Vector3(0, 10, -3)),
      radius: 3,
      height: 6,
    );
    final initial = await render([cylinder]);
    final tilted = Cylinder(
      frame: PlanarFrame(
        origin: rotate(cylinder.frame.origin) + translation,
        xAxis: rotate(cylinder.frame.xAxis),
        yAxis: rotate(cylinder.frame.yAxis),
      ),
      radius: 3,
      height: 6,
    );
    final image = await render(
      [tilted],
      cameraConfig: camera.copyWith(
        position: Vertex(translation),
        yaw: yaw,
        pitch: pitch,
      ),
      export: 'tilted-cylinder',
    );
    for (final x in [100, 110, 120, 130, 140]) {
      expect(pixel(image, x, 120)[3], 255);
      expect(pixel(image, x, 120)[0], closeTo(pixel(initial, x, 120)[0], 1));
    }
  });

  final objects = <CadObject>[
    Cylinder(
      frame: PlanarFrame.xy(origin: Vector3(-3.4, 12, -2.5)),
      radius: 2.5,
      height: 5,
    ),
    Tube(
      frame: PlanarFrame.xy(origin: Vector3(3.4, 12, -2.5)),
      outerRadius: 2.5,
      innerRadius: 1.2,
      height: 5,
    ),
    Cube(centerPosition: Vertex(Vector3(0, 15, -0.5)), size: 3),
    Objects([
      Edge(
        Vertex(Vector3(-10, 16, 0)),
        Vertex(Vector3(10, 16, 0)),
        curve: const LinearCadCurve(),
      ),
    ]),
  ];
  final views = <String, CameraConfig>{
    'front': view(Vector3(0, -5, 4), Vector3(0, 12, 0)),
    'orbit': view(Vector3(16, -3, 12), Vector3(0, 12, 0)),
    'rear': view(Vector3(-14, 27, 8), Vector3(0, 12, 0)),
    'top': view(Vector3(0, 12, 22), Vector3(0, 12, 0)),
    'clip': view(Vector3(3.4, 11, 0), Vector3(3.4, 15, 0), focal: 100),
  };
  for (final entry in views.entries) {
    for (final mode in CadRenderMode.values) {
      test(
        'repeatable ${entry.key} ${mode.name} view and frustum clipping',
        () async {
          final image = await render(
            objects,
            cameraConfig: entry.value,
            mode: mode,
            export: '${entry.key}-${mode.name}',
          );
          expect(
            [for (var i = 3; i < image.length; i += 4) image[i]]
                .any((a) => a > 0),
            isTrue,
          );
          final reversed = await render(
            objects.reversed.toList(),
            cameraConfig: entry.value,
            mode: mode,
          );
          if (mode == CadRenderMode.shaded) {
            expect(reversed, orderedEquals(image));
          } else {
            // Preserve original frame traversal. Intersecting antialiased red
            // strokes can differ slightly after quantization with object order.
            final difference = [
              for (var i = 0; i < image.length; i++)
                (image[i] - reversed[i]).abs(),
            ].reduce(math.max);
            expect(difference, lessThanOrEqualTo(2));
            expect(
              await render(objects, cameraConfig: entry.value, mode: mode),
              orderedEquals(image),
            );
          }
        },
      );
    }
  }
  test('export visual verification gallery on request', () async {
    final directory = Platform.environment['CURVED_RENDER_OUTPUT'];
    if (directory == null) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    var column = 0;
    for (final entry in views.entries) {
      var row = 0;
      for (final mode in [CadRenderMode.shaded, CadRenderMode.frame]) {
        canvas.save();
        canvas.translate(column * 240.0, row * 240.0);
        canvas.clipRect(const Rect.fromLTWH(0, 0, 240, 240));
        CadScenePainter(
          cameraConfig: entry.value,
          cadObjects: objects,
          renderMode: mode,
        ).paint(canvas, const Size(240, 240));
        canvas.restore();
        row++;
      }
      column++;
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1200, 480);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/gallery.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}

class Objects extends CadObject {
  Objects(this.primitives);
  final List<CadPrimitive> primitives;
  @override
  List<CadPrimitive> build() => primitives;
}
