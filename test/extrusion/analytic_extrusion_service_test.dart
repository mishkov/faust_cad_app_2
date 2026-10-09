import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../support/extrusion_fixtures.dart';
import '../support/extrusion_validation.dart';

const service = AnalyticExtrusionService();
ExtrusionResult extrude(
  RegionResult regions, {
  Iterable<String>? ids,
  PlanarFrame? frame,
  double distance = 5,
  bool reverse = false,
}) => service.extrude(
  regions: regions,
  regionIds: ids ?? regions.regions.map((r) => r.id),
  frame: frame ?? PlanarFrame.xy(),
  distance: distance,
  reverse: reverse,
);

void verify(
  ExtrusionResult result,
  PlanarFrame frame,
  double distance,
  bool reverse,
  List<double> expectedVolumes,
) {
  expect(
    result.diagnostics.where((d) => d.isError).map((d) => d.message),
    isEmpty,
  );
  expect(result.isValid, isTrue);
  expect(result.solids, hasLength(expectedVolumes.length));
  final measured =
      result.solids.map((s) => analyticBoundaryVolume(s, frame)).toList()
        ..sort();
  final expected = expectedVolumes.toList()..sort();
  for (var i = 0; i < expected.length; i++) {
    expect(measured[i], closeTo(expected[i], expected[i].abs() * 1e-10));
  }
  for (final volume in result.volumes) {
    final shell = volume.solid.shells.single;
    expect(shell.isClosed, isTrue);
    expect(volume.faces.map((o) => o.face), orderedEquals(shell.faces));
    final caps = volume.faces
        .where((o) => o.role != ExtrusionFaceRole.wall)
        .toList();
    expect(caps, hasLength(2));
    for (final cap in caps) {
      final plane = cap.face.surface as PlaneSurface;
      final isStart = cap.role == ExtrusionFaceRole.startCap;
      final signedDistance = distance * (reverse ? -1 : 1);
      expect(
        frame.signedDistance(plane.origin),
        closeTo(isStart ? 0 : signedDistance, 1e-10),
      );
      final expectedSign = (isStart ? -1 : 1) * (reverse ? -1 : 1);
      expect(
        cap.face.orientedNormal(plane.normal).dot(frame.normal),
        closeTo(expectedSign, 1e-12),
      );
      expect(cap.face.innerWires, hasLength(volume.profile.holes.length));
    }
    final uses = <({Face face, Edge edge})>[
      for (final face in shell.faces)
        for (final wire in [face.outerWire, ...face.innerWires])
          for (final edge in wire.edges) (face: face, edge: edge),
    ];
    for (final use in uses) {
      final mates = uses
          .where((u) => u.edge.hasSameBoundary(use.edge))
          .toList();
      expect(mates, hasLength(2));
      final mate = mates.singleWhere((u) => !identical(u.face, use.face));
      expect(
        identical(use.edge.begin, mate.edge.end),
        use.face.orientation == mate.face.orientation,
      );
      if (use.edge.curve is CircularCadCurve) {
        expect(use.edge.hasValidCircularEndpoints, isTrue);
        expect(mate.edge.curve, same(use.edge.curve));
      }
      for (final t in [0.0, 0.3, 0.5, 1.0]) {
        final p = use.edge.evaluate(t);
        final surface = use.face.surface;
        expect(
          frame.signedDistance(p) * (reverse ? -1 : 1),
          inInclusiveRange(-1e-10, distance + 1e-10),
        );
        if (surface is PlaneSurface) {
          expect(surface.signedDistance(p), closeTo(0, 1e-10));
        } else if (surface is CylinderSurface) {
          final delta = p - surface.origin;
          expect(
            (delta - surface.axis * delta.dot(surface.axis)).length,
            closeTo(surface.radius, 1e-10),
          );
        }
      }
    }
    for (final output in volume.faces) {
      expect(output.regions, isNotEmpty);
      for (final ref in output.regions) {
        expect(
          (ref.owner as RegionResult).resolve(ref).status,
          RegionResolutionStatus.resolved,
        );
      }
      if (output.role != ExtrusionFaceRole.wall) continue;
      final p = output.boundaries.single;
      final tangent = p.isArc
          ? Vector2(
                  -math.sin(p.startAngle! + p.sweepAngle! / 2),
                  math.cos(p.startAngle! + p.sweepAngle! / 2),
                ) *
                p.sweepAngle!
          : p.end - p.start;
      final outward = frame.xAxis * tangent.y - frame.yAxis * tangent.x;
      final surface = output.face.surface;
      final normal = surface is CylinderSurface
          ? output.face.orientedNormal(
              surface.normal(p.startAngle! + p.sweepAngle! / 2),
            )
          : output.face.orientedNormal((surface as PlaneSurface).normal);
      expect(normal.dot(outward.normalized()), closeTo(1, 1e-12));
      final midpoint = frame.localToWorld(p.pointAt(0.5));
      expect(
        volume.profile.locate(frame.projectToLocal(midpoint - normal * 1e-5)),
        RegionPointLocation.inside,
      );
      expect(
        volume.profile.locate(frame.projectToLocal(midpoint + normal * 1e-5)),
        RegionPointLocation.outside,
      );
    }
  }
}

void main() {
  final rectangle = profileArrangement(profileRectangle('r', 0, 0, 4, 3));
  final disk = profileArrangement([profileCircle('disk', 2, -1, 3)]);
  final nested = profileArrangement([
    profileCircle('outer', 0, 0, 3),
    profileCircle('inner', 0, 0, 1),
  ]);
  final mixed = profileArrangement([
    profileCircle('arc', 0, 0, 2),
    profileLine('diameter', -2, 0, 2, 0),
  ]);
  final overlap = profileArrangement([
    ...profileRectangle('a', 0, 0, 3, 2),
    ...profileRectangle('b', 2, 1, 3, 2),
  ]);
  final adjacent = profileArrangement([
    ...profileRectangle('a', 0, 0, 2, 3),
    ...profileRectangle('b', 2, 0, 2, 3),
  ]);
  final separated = profileArrangement([
    ...profileRectangle('a', 0, 0, 1, 2),
    profileCircle('b', 5, 0, 1),
  ]);
  final cases =
      <
        ({
          String name,
          RegionResult arrangement,
          Iterable<String>? ids,
          List<double> areas,
        })
      >[
        (name: 'rectangle', arrangement: rectangle, ids: null, areas: [12]),
        (name: 'disk', arrangement: disk, ids: null, areas: [9 * math.pi]),
        (
          name: 'annulus',
          arrangement: nested,
          ids: [nested.regions.singleWhere((r) => r.holes.isNotEmpty).id],
          areas: [8 * math.pi],
        ),
        (
          name: 'mixed line and arc semicircle',
          arrangement: mixed,
          ids: [
            mixed.regions
                .singleWhere(
                  (r) => r.locate(Vector2(0, 1)) == RegionPointLocation.inside,
                )
                .id,
          ],
          areas: [2 * math.pi],
        ),
        (
          name: 'overlapping rectangles',
          arrangement: overlap,
          ids: null,
          areas: [11],
        ),
        (
          name: 'shared boundary',
          arrangement: adjacent,
          ids: null,
          areas: [12],
        ),
        (
          name: 'separated components',
          arrangement: separated,
          ids: null,
          areas: [2, math.pi],
        ),
      ];
  final frames = [
    PlanarFrame.xy(),
    PlanarFrame.xz(origin: Vector3(11, -7, 4)),
    PlanarFrame(
      origin: Vector3(-4, 8, 3),
      xAxis: Vector3(1, 2, -1).normalized(),
      yAxis: Vector3(1, 0, 1).normalized(),
    ),
  ];
  for (final fixture in cases) {
    for (var f = 0; f < frames.length; f++) {
      for (final reverse in [false, true]) {
        test('${fixture.name}, frame $f, reverse $reverse', () {
          verify(
            extrude(
              fixture.arrangement,
              ids: fixture.ids,
              frame: frames[f],
              reverse: reverse,
            ),
            frames[f],
            5,
            reverse,
            fixture.areas.map((a) => a * 5).toList(),
          );
        });
      }
    }
  }
  test('circular overlap has independently calculated lens volume and analytic walls', () {
    final circles = profileArrangement([
      profileCircle('a', 0, 0, 2),
      profileCircle('b', 2, 0, 2),
    ]);
    final result = extrude(circles);
    final lens = 8 * math.acos(0.5) - math.sqrt(12);
    verify(result, PlanarFrame.xy(), 5, false, [(8 * math.pi - lens) * 5]);
    expect(
      result.volumes.single.faces
          .skip(2)
          .every((o) => o.face.surface is CylinderSurface),
      isTrue,
    );
    expect(result.volumes.single.faces.first.regions, hasLength(3));
  });
  test('filling a hole removes inner walls and retains all cap lineage', () {
    final result = extrude(nested);
    verify(result, PlanarFrame.xy(), 5, false, [9 * math.pi * 5]);
    expect(result.volumes.single.faces.first.regions, hasLength(2));
    expect(result.volumes.single.profile.holes, isEmpty);
    expect(
      result.volumes.single.faces
          .skip(2)
          .expand((o) => o.boundaries)
          .expand((p) => p.sources)
          .map((s) => s.inputId)
          .toSet(),
      {'outer'},
    );
  });
  test('multiple holes preserve inward walls', () {
    final arrangement = profileArrangement([
      ...profileRectangle('box', -5, -5, 10, 10),
      profileCircle('left', -2, 0, 1),
      profileCircle('right', 2, 0, 1),
    ]);
    final ids = [
      arrangement.regions.singleWhere((r) => r.holes.length == 2).id,
    ];
    for (final reverse in [false, true]) {
      verify(
        extrude(arrangement, ids: ids, reverse: reverse),
        PlanarFrame.xy(),
        5,
        reverse,
        [(100 - 2 * math.pi) * 5],
      );
    }
  });
  test(
    'positive sub-tolerance gaps stay separate without sharing vertices',
    () {
      final arrangement = profileArrangement([
        ...profileRectangle('a', 0, 0, 1, 1),
        ...profileRectangle('b', 1 + 1e-10, 0, 1, 1),
      ]);
      final result = extrude(arrangement);
      expect(result.isValid, isTrue);
      expect(result.solids, hasLength(2));
      final vertices = result.solids
          .map(
            (s) => Set<Vertex>.identity()
              ..addAll(
                s.shells.single.faces.expand(
                  (f) => f.outerWire.edges.map((e) => e.begin),
                ),
              ),
          )
          .toList();
      expect(vertices[0].intersection(vertices[1]), isEmpty);
      expect(
        result.volumes.every(
          (v) => v.faces.every((f) => f.regions.length == 1),
        ),
        isTrue,
      );
    },
  );
  test(
    'point contacts and touching holes return structured non-manifold errors',
    () {
      final pointContact = profileArrangement([
        ...profileRectangle('a', 0, 0, 1, 1),
        ...profileRectangle('b', 1, 1, 1, 1),
      ]);
      final tangent = profileArrangement([
        profileCircle('a', 0, 0, 1),
        profileCircle('b', 2, 0, 1),
      ]);
      final internal = profileArrangement([
        profileCircle('a', 0, 0, 2),
        profileCircle('b', 1, 0, 1),
      ]);
      for (final result in [
        extrude(pointContact),
        extrude(tangent),
        extrude(
          internal,
          ids: [internal.regions.singleWhere((r) => r.holes.isNotEmpty).id],
        ),
      ]) {
        expect(result.isValid, isFalse);
        expect(result.solids, isEmpty);
        final d = result.diagnostics.singleWhere((d) => d.isError);
        expect(d.code, 'nonManifoldSelection');
        expect(d.regionIds, isNotEmpty);
        expect(d.inputIds, isNotEmpty);
      }
      expect(extrude(tangent, ids: [tangent.regions.first.id]).isValid, isTrue);
      expect(extrude(internal).isValid, isTrue);
    },
  );
  test('invalid distances, empty/stale selections and invalid profiles reject atomically', () {
    for (final d in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final result = extrude(rectangle, distance: d);
      expect(result.isValid, isFalse);
      expect(result.solids, isEmpty);
      expect(
        result.diagnostics.map((d) => d.code),
        contains('invalidDistance'),
      );
    }
    expect(
      extrude(rectangle, ids: []).diagnostics.map((d) => d.code),
      contains('emptySelection'),
    );
    expect(
      extrude(rectangle, ids: ['stale']).diagnostics.map((d) => d.code),
      contains('unknownRegion'),
    );
    final open = profileArrangement([profileLine('open', 0, 0, 1, 0)]);
    expect(extrude(open).isValid, isFalse);
    expect(
      extrude(open).diagnostics.map((d) => d.code),
      contains('openBoundary'),
    );
    expect(
      extrude(profileArrangement([profileCircle('huge', 0, 0, 1e200)]))
          .diagnostics
          .map((d) => d.code),
      contains('invalidProfile'),
    );
  });
  test(
    'collapsed placement, overflow and volume underflow publish no solids',
    () {
      final collapse = extrude(
        rectangle,
        frame: PlanarFrame.xy(origin: Vector3(0, 0, 1e20)),
        distance: 1,
      );
      final overflow = extrude(
        rectangle,
        frame: PlanarFrame.xy(origin: Vector3(0, 0, 1e308)),
        distance: 1e308,
      );
      final tiny = profileArrangement(
        profileRectangle('tiny', 0, 0, 1e-100, 1e-100),
      );
      final underflow = extrude(tiny, distance: 1e-200);
      for (final result in [collapse, overflow, underflow]) {
        expect(result.isValid, isFalse);
        expect(result.solids, isEmpty);
        expect(
          result.diagnostics.map((d) => d.code),
          contains('unrepresentableGeometry'),
        );
      }
    },
  );
  test('duplicate selection is idempotent and calls own their topology', () {
    final ids = rectangle.regions.map((r) => r.id).toList();
    final a = extrude(rectangle, ids: [...ids, ...ids]);
    final b = extrude(rectangle);
    expect(a.solids, hasLength(1));
    a
            .solids
            .single
            .shells
            .single
            .faces
            .first
            .outerWire
            .edges
            .first
            .begin
            .vector
            .x =
        999;
    verify(b, PlanarFrame.xy(), 5, false, [60]);
    expect(rectangle.regions.single.area, 12);
    expect(() => b.volumes.clear(), throwsUnsupportedError);
    expect(() => b.volumes.single.faces.clear(), throwsUnsupportedError);
  });
  test(
    'split and duplicate provenance survive; cancelled internal edges vanish',
    () {
      final arrangement = profileArrangement([
        ...profileRectangle('r', 0, 0, 4, 3),
        profileLine('duplicate', 4, 0, 0, 0),
        profileLine('split', 2, 0, 2, 3),
      ]);
      final volume = extrude(arrangement, reverse: true).volumes.single;
      expect(volume.faces.first.regions, hasLength(2));
      final sources = volume.faces
          .where((f) => f.role == ExtrusionFaceRole.wall)
          .expand((f) => f.boundaries)
          .expand((p) => p.sources)
          .toList();
      expect(sources.map((s) => s.inputId), isNot(contains('split')));
      final duplicate = sources.where((s) => s.inputId == 'duplicate').toList();
      expect(duplicate, hasLength(2));
      expect(duplicate.every((s) => s.startParameter > s.endParameter), isTrue);
      expect(
        duplicate
            .map((s) => (s.startParameter - s.endParameter).abs())
            .reduce((a, b) => a + b),
        closeTo(1, 1e-12),
      );
      final keys = volume.faces.map((f) => f.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(extrude(arrangement).volumes.single.faces.map((f) => f.key), keys);
    },
  );
  test('a later component failure discards previously built volumes', () {
    final arrangement = profileArrangement([
      ...profileRectangle('a', 0, 0, 4, 3),
      ...profileRectangle('b', 20, 0, 0.25, 1),
    ]);
    expect(arrangement.isValid, isTrue);
    expect(arrangement.regions, hasLength(2));
    final frame = PlanarFrame.xy(origin: Vector3(1e16, 0, 0));
    expect(
      extrude(
        arrangement,
        ids: [arrangement.regions.first.id],
        frame: frame,
      ).isValid,
      isTrue,
    );
    final result = extrude(arrangement, frame: frame);
    expect(result.isValid, isFalse);
    expect(result.volumes, isEmpty);
    expect(
      result.diagnostics.map((d) => d.code),
      contains('unrepresentableGeometry'),
    );
  });

  test('an island within an annular hole stays a separate body with its own lineage', () {
    final arrangement = profileArrangement([
      profileCircle('outer', 0, 0, 4),
      profileCircle('hole', 0, 0, 2),
      profileCircle('island', 0, 0, 1),
    ]);
    final selected = arrangement.regions
        .where(
          (r) =>
              r.locate(Vector2(3, 0)) == RegionPointLocation.inside ||
              r.locate(Vector2.zero()) == RegionPointLocation.inside,
        )
        .map((r) => r.id)
        .toList();
    final result = extrude(arrangement, ids: selected);
    verify(result, PlanarFrame.xy(), 5, false, [12 * math.pi * 5, math.pi * 5]);
    expect(
      result.volumes.every((v) => v.faces.every((f) => f.regions.length == 1)),
      isTrue,
    );
  });

  test('partially shared boundaries cancel without a hidden internal wall', () {
    final arrangement = profileArrangement([
      ...profileRectangle('a', 0, 0, 3, 3),
      ...profileRectangle('b', 3, 1, 2, 1),
    ]);
    final result = extrude(arrangement);
    verify(result, PlanarFrame.xy(), 5, false, [55]);
    expect(result.volumes.single.faces.first.regions, hasLength(2));
  });
}
