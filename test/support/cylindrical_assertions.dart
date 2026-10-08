import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void expectCylindricalShell(
  Shell shell, {
  required PlanarFrame frame,
  required double radius,
  required double height,
  required int patchCount,
  double? innerRadius,
}) {
  final hollow = innerRadius != null;
  expect(shell.isClosed, isTrue);
  expect(shell.faces, hasLength(2 + patchCount * (hollow ? 2 : 1)));
  final caps = shell.faces.where((f) => f.surface is PlaneSurface).toList();
  final walls = shell.faces.where((f) => f.surface is CylinderSurface).toList();
  expect(caps, hasLength(2));
  final wallSurfaces = Set<CylinderSurface>.identity()
    ..addAll(walls.map((f) => f.surface as CylinderSurface));
  expect(wallSurfaces, hasLength(hollow ? 2 : 1));
  for (final surface in wallSurfaces) {
    expect(
      walls.where((f) => identical(f.surface, surface)),
      hasLength(patchCount),
    );
  }
  for (final cap in caps) {
    final plane = cap.surface as PlaneSurface;
    final axial = (plane.origin - frame.origin).dot(frame.normal);
    final bottom = axial.abs() < 1e-12;
    expect(axial, closeTo(bottom ? 0 : height, 1e-12));
    expect(
      (plane.origin - (frame.origin + frame.normal * (bottom ? 0 : height)))
          .length,
      lessThan(1e-12),
    );
    final normal = cap.orientedNormal(plane.normal);
    expect(normal.dot(frame.normal), closeTo(bottom ? -1 : 1, 1e-12));
    expect(cap.innerWires, hasLength(hollow ? 1 : 0));
    for (final wire in [cap.outerWire, ...cap.innerWires]) {
      final isHole = !identical(wire, cap.outerWire);
      final expectedRadius = isHole ? innerRadius! : radius;
      expect(wire.edges, hasLength(patchCount));
      for (final edge in wire.edges) {
        expect(edge.curve, isA<CircularCadCurve>());
        expect(
          edge.trim!.sweepAngle.abs(),
          closeTo(2 * math.pi / patchCount, 1e-12),
        );
        for (final t in [0.0, 0.25, 0.5, 1.0]) {
          final point = edge.evaluate(t);
          expect(plane.signedDistance(point), closeTo(0, 1e-12));
          expect((point - plane.origin).length, closeTo(expectedRadius, 1e-12));
        }
        final radial = edge.evaluate(0.5) - plane.origin;
        final tangent = edge.tangent(0.5) * _sign(cap);
        expect(
          radial.cross(tangent).dot(normal) * (isHole ? -1 : 1),
          greaterThan(0),
        );
      }
    }
  }
  for (final wall in walls) {
    final surface = wall.surface as CylinderSurface;
    final inner = hollow && surface.radius == innerRadius;
    expect(surface.radius, inner ? innerRadius : radius);
    expect(wall.innerWires, isEmpty);
    final edges = wall.outerWire.edges;
    expect(edges, hasLength(4));
    expect(edges.where((e) => e.curve is CircularCadCurve), hasLength(2));
    expect(edges.where((e) => e.curve is LinearCadCurve), hasLength(2));
    for (final edge in edges) {
      for (final t in [0.0, 0.25, 0.5, 1.0]) {
        final point = edge.evaluate(t);
        final delta = point - frame.origin;
        final axial = delta.dot(frame.normal);
        expect(axial, inInclusiveRange(-1e-12, height + 1e-12));
        expect(
          (delta - frame.normal * axial).length,
          closeTo(surface.radius, 1e-12),
        );
        if (edge.curve is CircularCadCurve) {
          expect(
            axial,
            closeTo(identical(edge, edges.first) ? 0 : height, 1e-12),
          );
        }
      }
    }
    final angle = edges.first.trim!.angleAt(0.5);
    final normal = wall.orientedNormal(surface.normal(angle));
    expect(normal.dot(surface.normal(angle)), closeTo(inner ? -1 : 1, 1e-12));
    // Interior points follow the same analytic cylinder as both boundary arcs.
    final point = surface.evaluate(angle, height / 2);
    final delta = point - frame.origin;
    expect(delta.dot(frame.normal), closeTo(height / 2, 1e-12));
    expect(
      (delta - frame.normal * (height / 2)).length,
      closeTo(surface.radius, 1e-12),
    );
    final epsilon = (hollow ? radius - innerRadius : radius) * 0.01;
    for (final direction in [-1, 1]) {
      final probe = delta + normal * (direction * epsilon);
      final radialLength =
          (probe - frame.normal * probe.dot(frame.normal)).length;
      final inMaterial =
          radialLength < radius && (!hollow || radialLength > innerRadius);
      expect(inMaterial, direction < 0);
    }
  }
  final uses = <({Face face, Edge edge})>[
    for (final face in shell.faces)
      for (final wire in [face.outerWire, ...face.innerWires])
        for (final edge in wire.edges) (face: face, edge: edge),
  ];
  final vertices = Set<Vertex>.identity()
    ..addAll(uses.map((u) => u.edge.begin));
  expect(vertices, hasLength(patchCount * (hollow ? 4 : 2)));
  for (final use in uses) {
    final matches = uses
        .where((u) => u.edge.hasSameBoundary(use.edge))
        .toList();
    expect(matches, hasLength(2));
    final mate = matches.singleWhere((u) => !identical(u.face, use.face));
    final sameOrientation = _sign(use.face) == _sign(mate.face);
    expect(identical(use.edge.begin, mate.edge.end), sameOrientation);
    if (use.edge.curve is CircularCadCurve) {
      expect(mate.edge.curve, same(use.edge.curve));
      expect(
        use.edge.trim!.sweepAngle * _sign(use.face),
        closeTo(-mate.edge.trim!.sweepAngle * _sign(mate.face), 1e-12),
      );
    }
  }
  // Annular caps each contribute zero to Euler characteristic; disk caps one.
  final euler =
      vertices.length - uses.length ~/ 2 + walls.length + (hollow ? 0 : 2);
  expect(euler, hollow ? 0 : 2);
}

double _sign(Face face) =>
    face.orientation == FaceOrientation.forward ? 1.0 : -1.0;
