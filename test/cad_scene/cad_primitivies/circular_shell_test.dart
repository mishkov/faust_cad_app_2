import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  late CircularCadCurve circle;
  late Wire boundary;
  Face face(
    Wire wire, {
    FaceOrientation orientation = FaceOrientation.forward,
  }) => Face(
    surface: circle.frame.plane,
    outerWire: wire,
    orientation: orientation,
  );

  setUp(() {
    circle = CircularCadCurve(frame: PlanarFrame.xy(), radius: 1);
    boundary = Wire.circular(circle);
  });

  // These paired disks exercise topology only; they do not enclose a volume.
  test('curved pairing accepts reversals, including two semicircles', () {
    for (final count in [2, 3, 4]) {
      final wire = Wire.circular(circle, arcCount: count);
      expect(
        Shell(faces: [face(wire), face(wire.reversed())]).isClosed,
        isTrue,
      );
    }
    expect(Shell(faces: [face(boundary), face(boundary)]).isClosed, isFalse);
    expect(Shell(faces: [face(boundary)]).isClosed, isFalse);
    expect(
      Shell(faces: [face(boundary), face(boundary.reversed()), face(boundary)])
          .isClosed,
      isFalse,
    );
  });

  test('complementary arcs with shared endpoints and curve do not pair', () {
    final first = boundary.edges.first;
    final wrong = Edge(
      first.end,
      first.begin,
      curve: circle,
      trim: CircularTrim(
        startAngle: first.trim!.endAngle,
        sweepAngle: 2 * math.pi - first.trim!.sweepAngle,
      ),
    );
    final reverse = boundary.reversed();
    final wrongBoundary = Wire([...reverse.edges.take(3), wrong]);
    expect(
      Shell(faces: [face(boundary), face(wrongBoundary)]).isClosed,
      isFalse,
    );
    expect(first.hasSameBoundary(wrong), isFalse);
  });

  test(
    'independent but coincident circles and vertices cannot close a shell',
    () {
      final otherCircle = CircularCadCurve(
        frame: circle.frame,
        radius: circle.radius,
      );
      final reverse = boundary.reversed();
      final otherBoundary = Wire([
        for (final edge in reverse.edges)
          Edge(edge.begin, edge.end, curve: otherCircle, trim: edge.trim),
      ]);
      expect(
        Shell(faces: [face(boundary), face(otherBoundary)]).isClosed,
        isFalse,
      );
      expect(
        () => Shell(faces: [face(boundary), face(Wire.circular(otherCircle))]),
        throwsArgumentError,
      );
    },
  );

  test('independent trims on a shared curve match reversed boundaries', () {
    final reverse = boundary.reversed();
    final rebuilt = Wire([
      for (final edge in reverse.edges)
        Edge(
          edge.begin,
          edge.end,
          curve: circle,
          trim: CircularTrim(
            startAngle: edge.trim!.startAngle + 2 * math.pi,
            sweepAngle: edge.trim!.sweepAngle,
          ),
        ),
    ]);
    expect(Shell(faces: [face(boundary), face(rebuilt)]).isClosed, isTrue);
  });

  test(
    'face reversal changes material normal and effective traversal only',
    () {
      final forward = face(boundary);
      final reverse = forward.reversed();
      expect(reverse.orientation, FaceOrientation.reversed);
      expect(reverse.surface, same(forward.surface));
      expect(reverse.outerWire, same(boundary));
      expect(reverse.reversed().orientation, FaceOrientation.forward);
      final normal = circle.frame.normal;
      expect(forward.orientedNormal(normal), Vector3(0, 0, 1));
      expect(reverse.orientedNormal(normal), Vector3(0, 0, -1));
      expect(normal, Vector3(0, 0, 1));
      expect(Shell(faces: [forward, reverse]).isClosed, isTrue);
      expect(
        Shell(faces: [forward, face(boundary.reversed()).reversed()]).isClosed,
        isFalse,
      );
      final faces = [forward, face(boundary.reversed())];
      expect(
        Shell(faces: [for (final f in faces) f.reversed()]).isClosed,
        isTrue,
      );
    },
  );

  test('circular hole boundaries participate in pairing and face reversal', () {
    final outer = Wire.circular(
      CircularCadCurve(frame: circle.frame, radius: 3),
    );
    final annulus = Face(
      surface: circle.frame.plane,
      outerWire: outer,
      innerWires: [boundary.reversed()],
    );
    final mate = Face(
      surface: annulus.surface,
      outerWire: outer.reversed(),
      innerWires: [boundary],
    );
    expect(Shell(faces: [annulus, mate]).isClosed, isTrue);
    expect(Shell(faces: [annulus, face(outer.reversed())]).isClosed, isFalse);
  });

  test('endpoint mutations invalidate circular shells', () {
    final shell = Shell(faces: [face(boundary), face(boundary.reversed())]);
    expect(shell.isClosed, isTrue);
    boundary.edges.first.begin.vector.z = 0.1;
    expect(shell.isClosed, isFalse);
  });

  test('circular skins touching only at a vertex remain nonmanifold', () {
    final shared = boundary.edges.first.begin;
    final otherCircle = CircularCadCurve(
      frame: PlanarFrame.xy(origin: Vector3(2, 0, 0)),
      radius: 1,
    );
    final other = Wire.circular(otherCircle, startAngle: math.pi);
    final vertices = [
      shared,
      for (final edge in other.edges.skip(1)) edge.begin,
    ];
    final touching = Wire([
      for (var i = 0; i < 4; i++)
        Edge(
          vertices[i],
          vertices[(i + 1) % 4],
          curve: otherCircle,
          trim: other.edges[i].trim,
        ),
    ]);
    expect(
      Shell(
        faces: [
          face(boundary),
          face(boundary.reversed()),
          face(touching),
          face(touching.reversed()),
        ],
      ).isClosed,
      isFalse,
    );
  });

  test('collapsed linear edges are still rejected by shell validation', () {
    final vertex = Vertex(Vector3.zero());
    final wire = Wire([Edge(vertex, vertex, curve: const LinearCadCurve())]);
    final collapsed = face(wire);
    expect(Shell(faces: [collapsed, collapsed.reversed()]).isClosed, isFalse);
  });
}
