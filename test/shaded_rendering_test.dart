import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final camera = CameraConfig(
    position: Vertex(Vector3.zero()),
    yaw: 0,
    pitch: 0,
    focalLength: 100,
    focusDistance: 10,
  );

  Future<Uint8List> render(
    List<CadObject> objects, {
    CameraConfig? view,
    CadRenderMode mode = CadRenderMode.shaded,
  }) async {
    final recorder = ui.PictureRecorder();
    CadScenePainter(
      cameraConfig: view ?? camera,
      cadObjects: objects,
      renderMode: mode,
    ).paint(Canvas(recorder), const Size(200, 200));
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 200);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }

  List<int> pixel(Uint8List image, int x, int y) =>
      image.sublist((y * 200 + x) * 4, (y * 200 + x) * 4 + 4);

  testWidgets('scene defaults to frame and forwards changes to its painter', (
    tester,
  ) async {
    for (final mode in [CadRenderMode.frame, CadRenderMode.shaded]) {
      await tester.pumpWidget(
        SizedBox(
          width: 200,
          height: 200,
          child: mode == CadRenderMode.frame
              ? CadScene(cameraConfig: camera, cadObjects: const [])
              : CadScene(
                  cameraConfig: camera,
                  cadObjects: const [],
                  renderMode: mode,
                ),
        ),
      );
      final paint = tester.widget<CustomPaint>(find.byType(CustomPaint));
      expect((paint.painter! as CadScenePainter).renderMode, mode);
    }
  });

  test(
    'shaded cube is opaque while frame retains its empty interior',
    () async {
      final cube = Cube(centerPosition: Vertex(Vector3(0, 8, 0)), size: 4);
      final shaded = await render([cube]);
      final frame = await render([cube], mode: CadRenderMode.frame);
      final center = pixel(shaded, 100, 100);
      expect(center[3], 255);
      expect(center[0], center[1]);
      expect(center[1], center[2]);
      expect(pixel(frame, 100, 100)[3], 0);
    },
  );

  test('holes leave transparent openings and expose rear geometry', () async {
    final front = _Objects([
      _face(depth: 5, halfSize: 3, holes: [_rectangle(0.8, 5)]),
    ]);
    final behind = _Objects([_line(Vector3(-4, 10, 0), Vector3(4, 10, 0))]);
    final alone = await render([front]);
    expect(pixel(alone, 100, 100)[3], 0);
    expect(pixel(alone, 130, 100)[3], 255);
    final combined = await render([front, behind]);
    expect(pixel(combined, 100, 100)[0], greaterThan(100));
    expect(pixel(combined, 100, 100)[1], lessThan(100));
    expect(pixel(combined, 130, 100), pixel(alone, 130, 100));
    expect(await render([behind, front]), orderedEquals(combined));
  });

  test(
    'fully hidden objects and their outlines do not change the image',
    () async {
      final front = Cube(centerPosition: Vertex(Vector3(0, 8, 0)), size: 4);
      final back = Cube(centerPosition: Vertex(Vector3(0, 14, 0)), size: 3);
      final alone = await render([front]);
      expect(await render([front, back]), orderedEquals(alone));
      expect(await render([back, front]), orderedEquals(alone));
    },
  );

  test(
    'partial occlusion clips rear edges and retains foreground edges',
    () async {
      final face = _Objects([_face(depth: 5, halfSize: 2)]);
      final rear = _Objects([_line(Vector3(-10, 10, 0), Vector3(10, 10, 0))]);
      final front = _Objects([_line(Vector3(-1, 2, 0.4), Vector3(1, 2, 0.4))]);
      final image = await render([face, rear, front]);
      expect(pixel(image, 100, 100)[0], pixel(image, 100, 100)[1]);
      expect(pixel(image, 20, 100)[0], greaterThan(100));
      expect(pixel(image, 20, 100)[1], lessThan(50));
      expect(pixel(image, 100, 80)[0], greaterThan(100));
      expect(
        pixel(image, 100, 80)[0],
        greaterThan(pixel(image, 100, 80)[1] + 50),
      );
    },
  );

  test(
    'intersecting faces use local depths instead of whole-face sorting',
    () async {
      final a = _Objects([_slantedFace(0.08)]);
      final b = _Objects([_slantedFace(-0.08)]);
      final image = await render([a, b]);
      final aOnly = await render([a]);
      final bOnly = await render([b]);
      expect(pixel(image, 140, 100), pixel(aOnly, 140, 100));
      expect(pixel(image, 60, 100), pixel(bOnly, 60, 100));
      expect(pixel(image, 140, 100), isNot(pixel(image, 60, 100)));
      expect(await render([b, a]), orderedEquals(image));
    },
  );

  test(
    'camera-fixed lighting keeps equivalent view normals equally lit',
    () async {
      final initial = await render([
        _Objects([_slantedFace(-0.08)]),
      ]);
      const yaw = 0.7;
      const pitch = -0.4;
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

      final face = _slantedFace(-0.08);
      final surface = face.surface as PlaneSurface;
      final transformed = Face(
        surface: PlaneSurface(
          origin: rotate(surface.origin) + translation,
          normal: rotate(surface.normal),
        ),
        outerWire: _wire([
          for (final edge in face.outerWire.edges)
            rotate(edge.begin.vector) + translation,
        ]),
      );
      final image = await render(
        [
          _Objects([transformed]),
        ],
        view: camera.copyWith(
          position: Vertex(translation),
          yaw: yaw,
          pitch: pitch,
        ),
      );
      expect(pixel(image, 100, 100), pixel(initial, 100, 100));
      final dark = await render([
        _Objects([_slantedFace(0.08)]),
      ]);
      expect(
        pixel(initial, 100, 100)[0],
        greaterThan(pixel(dark, 100, 100)[0]),
      );
    },
  );

  test(
    'near-plane crossing faces fill only finite clipped viewport regions',
    () async {
      final face = Face(
        surface: PlaneSurface(
          origin: Vector3(0, 0, -0.5),
          normal: Vector3(0, 0.5, -1),
        ),
        outerWire: _wire([
          Vector3(-2, -1, -1),
          Vector3(2, -1, -1),
          Vector3(2, 2, 0.5),
          Vector3(-2, 2, 0.5),
        ]),
      );
      final image = await render([
        _Objects([face]),
      ]);
      expect(pixel(image, 100, 100)[3], 255);
      expect(pixel(image, 100, 20)[3], 0);
      final behind = await render([
        _Objects([_face(depth: -2, halfSize: 1)]),
      ]);
      expect(behind, everyElement(0));
    },
  );

  test('empty shaded viewport draws nothing', () {
    final painter = CadScenePainter(
      cameraConfig: camera,
      cadObjects: [
        _Objects([_face(depth: 5, halfSize: 2)]),
      ],
      renderMode: CadRenderMode.shaded,
    );
    expect((Canvas canvas) => painter.paint(canvas, Size.zero), paintsNothing);
  });
}

Face _face({
  required double depth,
  required double halfSize,
  List<Wire> holes = const [],
}) => Face(
  surface: PlaneSurface(
    origin: Vector3(0, depth, 0),
    normal: Vector3(0, -1, 0),
  ),
  outerWire: _rectangle(halfSize, depth),
  innerWires: holes,
);

Face _slantedFace(double slope) {
  // Same projected rectangle for both slopes; reciprocal depth changes sides.
  final points = [
    for (final (x, z) in [(-0.7, -0.7), (0.7, -0.7), (0.7, 0.7), (-0.7, 0.7)])
      Vector3(x, 1, z) / (0.2 + slope * x),
  ];
  return Face(
    surface: PlaneSurface(origin: points.first, normal: Vector3(slope, 0.2, 0)),
    outerWire: _wire(points),
  );
}

Wire _rectangle(double halfSize, double depth) => _wire([
  Vector3(-halfSize, depth, -halfSize),
  Vector3(halfSize, depth, -halfSize),
  Vector3(halfSize, depth, halfSize),
  Vector3(-halfSize, depth, halfSize),
]);

Wire _wire(List<Vector3> points) {
  final vertices = points.map(Vertex.new).toList();
  return Wire([
    for (var i = 0; i < vertices.length; i++)
      Edge(
        vertices[i],
        vertices[(i + 1) % vertices.length],
        curve: const LinearCadCurve(),
      ),
  ]);
}

Edge _line(Vector3 begin, Vector3 end) =>
    Edge(Vertex(begin), Vertex(end), curve: const LinearCadCurve());

class _Objects extends CadObject {
  _Objects(this.primitives);
  final List<CadPrimitive> primitives;
  @override
  List<CadPrimitive> build() => primitives;
}
