import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/analytic_continuity.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_scene_mesh.dart';
import 'package:faust_cad_app_2/cad_scene/selection/selection_measurement.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_hit.dart';
import 'package:faust_cad_app_2/cad_scene/selection/viewport_picker.dart';
import 'package:faust_cad_app_2/document/evaluated_geometry.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../../support/attachment_fixtures.dart';
import '../../support/extrusion_fixtures.dart';

const viewport = Size(400, 400);
final camera = CameraConfig(
  position: Vertex(Vector3(0, 0, 20)),
  yaw: 0,
  pitch: -math.pi / 2,
  focalLength: 200,
  focusDistance: 20,
);
ViewportPicker picker(List<CadPrimitive> geometry) => ViewportPicker(
  evaluated: EvaluatedGeometry(geometry: geometry, bodies: {}, faces: {}),
);
Offset project(Vector3 point) {
  final projection = CameraProjection(camera);
  final p = projection.project(
    projection.toCameraSpace(point),
    screen: viewport,
  );
  return Offset(p.x, p.y);
}

ViewportHit pick(ViewportPicker scene, Vector3 point) => scene.pick(
  camera: camera,
  viewport: viewport,
  position: project(point),
  mode: ViewportSelectionMode.inspect,
)!;
Solid extrudedCircle(PlanarFrame frame) {
  final regions = profileArrangement([profileCircle('circle', 0, 0, 3)]);
  return const AnalyticExtrusionService()
      .extrude(
        regions: regions,
        regionIds: regions.regions.map((r) => r.id),
        frame: frame,
        distance: 6,
      )
      .solids
      .single;
}

List<Vector3> uploadedLinePoints(List<double> lines) => [
  for (var i = 0; i < lines.length; i += 90) ...[
    Vector3(
      lines[i] + lines[i + 3],
      lines[i + 1] + lines[i + 4],
      lines[i + 2] + lines[i + 5],
    ),
    Vector3(
      lines[i + 6] + lines[i + 9],
      lines[i + 7] + lines[i + 10],
      lines[i + 8] + lines[i + 11],
    ),
  ],
];

void main() {
  for (final rotated in [false, true]) {
    test(
      'either extruded semicircle selects the complete rim, rotated=$rotated',
      () {
        final frame = rotated ? tiltedFrame(0.4) : PlanarFrame.xy();
        final solid = extrudedCircle(frame);
        final scene = picker([solid]);
        final hits = [
          for (final angle in [math.pi / 4, 5 * math.pi / 4])
            pick(
              scene,
              frame.localToWorld(
                    Vector2(3 * math.cos(angle), 3 * math.sin(angle)),
                  ) +
                  frame.normal * 6,
            ),
        ];
        for (final hit in hits) {
          expect(hit.owner, same(solid));
          expect(hit.edges, hasLength(2));
          expect(AnalyticContinuity.isFullCircle(hit.edges), isTrue);
          final measurement = SelectionMeasurement.fromHit(hit);
          expect(measurement.kind, 'Circle');
          expect(measurement.values.first.value, closeTo(6 * math.pi, 1e-9));
          expect(measurement.values.last.value, 3);
          expect(
            hit.edges.any((edge) => edge.hasSameBoundary(hit.edge!)),
            isTrue,
          );
          final points = uploadedLinePoints(
            MetalSceneMesh(scene.scene)
                .hoverLines(null, selectedEdge: hit.edge),
          );
          final local = points.map(frame.projectToLocal).toList();
          expect(local.map((p) => p.x).reduce(math.min), lessThan(-2.9));
          expect(local.map((p) => p.x).reduce(math.max), greaterThan(2.9));
          expect(local.map((p) => p.y).reduce(math.min), lessThan(-2.9));
          expect(local.map((p) => p.y).reduce(math.max), greaterThan(2.9));
          expect(
            points.map(frame.signedDistance),
            everyElement(closeTo(6, 1e-6)),
          );
        }
        expect(hits.last.edges, unorderedEquals(hits.first.edges));
      },
    );
  }

  test('hole rim selects its full circle without the outer or bottom rims', () {
    final solid = Tube(
      frame: PlanarFrame.xy(),
      outerRadius: 4,
      innerRadius: 2,
      height: 6,
    ).build().single;
    final scene = picker([solid]);
    final hit = pick(scene, Vector3(math.sqrt(2), math.sqrt(2), 6));
    expect(hit.edges, hasLength(4));
    expect(SelectionMeasurement.fromHit(hit).kind, 'Circle');
    expect(
      SelectionMeasurement.fromHit(hit).values.first.value,
      closeTo(4 * math.pi, 1e-9),
    );
    final points = uploadedLinePoints(
      MetalSceneMesh(scene.scene).hoverLines(null, selectedEdge: hit.edge),
    );
    for (final point in points) {
      expect(point.z, closeTo(6, 1e-6));
      expect(Vector2(point.x, point.y).length, closeTo(2, 1e-6));
    }
  });

  test(
    'coincident rims from independent bodies remain independent selections',
    () {
      final first = extrudedCircle(PlanarFrame.xy());
      final second = extrudedCircle(PlanarFrame.xy());
      final hit = pick(
        picker([first, second]),
        Vector3(3 / math.sqrt(2), 3 / math.sqrt(2), 6),
      );
      expect(hit.owner, same(first));
      final firstEdges = {
        for (final face in first.shells.single.faces)
          for (final wire in [face.outerWire, ...face.innerWires])
            ...wire.edges,
      };
      expect(hit.edges, everyElement(isIn(firstEdges)));
      expect(hit.edges, hasLength(2));
    },
  );

  test(
    'partial circular arcs retain individual selection and their arc length',
    () {
      final frame = PlanarFrame.xy(origin: Vector3(0, 0, 6));
      final curve = CircularCadCurve(frame: frame, radius: 3);
      final vertices = [
        for (final angle in [0.0, math.pi / 2, math.pi])
          Vertex(curve.evaluate(angle)),
      ];
      final arcs = [
        for (var i = 0; i < 2; i++)
          Edge(
            vertices[i],
            vertices[i + 1],
            curve: curve,
            trim: CircularTrim(
              startAngle: i * math.pi / 2,
              sweepAngle: math.pi / 2,
            ),
          ),
      ];
      final face = Face(
        surface: frame.plane,
        outerWire: Wire([
          ...arcs,
          Edge(vertices.last, vertices.first, curve: const LinearCadCurve()),
        ]),
      );
      final hit = pick(picker([face]), curve.evaluate(math.pi / 4));
      expect(hit.edge, same(arcs.first));
      expect(hit.edges, [arcs.first]);
      final measurement = SelectionMeasurement.fromHit(hit);
      expect(measurement.kind, 'Arc');
      expect(measurement.values.first.value, closeTo(3 * math.pi / 2, 1e-9));
    },
  );

  for (final renderMode in CadRenderMode.values) {
    test(
      'whole-rim Canvas highlight respects visibility in $renderMode',
      () async {
        final solid = extrudedCircle(PlanarFrame.xy());
        final foreground = rectangle(PlanarFrame.xy(origin: Vector3(4, 0, 8)));
        final scene = picker([solid, foreground]);
        final cap = solid.shells.single.faces.firstWhere(
          (face) => face.outerWire.edges.every(
            (edge) => (edge.begin.vector.z - 6).abs() < 1e-9,
          ),
        );
        final recorder = ui.PictureRecorder();
        CadScenePainter(
          cameraConfig: camera,
          evaluatedScene: scene.scene,
          renderMode: renderMode,
          selectedEdge: cap.outerWire.edges.first,
        ).paint(Canvas(recorder), viewport);
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final bytes = (await image.toByteData())!;
        bool cyanNear(double angle) {
          final point = project(
            Vector3(3 * math.cos(angle), 3 * math.sin(angle), 6),
          );
          for (var y = point.dy.floor() - 2; y <= point.dy.ceil() + 2; y++) {
            for (var x = point.dx.floor() - 2; x <= point.dx.ceil() + 2; x++) {
              final i = (y * 400 + x) * 4;
              if (bytes.getUint8(i + 1) > bytes.getUint8(i) + 60 &&
                  bytes.getUint8(i + 2) > bytes.getUint8(i) + 60) {
                return true;
              }
            }
          }
          return false;
        }

        expect(cyanNear(3 * math.pi / 4), isTrue);
        expect(cyanNear(5 * math.pi / 4), isTrue);
        expect(cyanNear(math.pi / 4), renderMode == CadRenderMode.frame);
        expect(cyanNear(7 * math.pi / 4), renderMode == CadRenderMode.frame);
        image.dispose();
        picture.dispose();
      },
    );
  }
}
