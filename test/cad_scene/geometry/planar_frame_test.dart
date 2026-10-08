import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

void expectVector3(Vector3 actual, Vector3 expected, [double epsilon = 1e-12]) {
  expect(actual.x, closeTo(expected.x, epsilon));
  expect(actual.y, closeTo(expected.y, epsilon));
  expect(actual.z, closeTo(expected.z, epsilon));
}

void expectVector2(Vector2 actual, Vector2 expected) {
  expect(actual.x, closeTo(expected.x, 1e-12));
  expect(actual.y, closeTo(expected.y, 1e-12));
}

final invalidVectors = [
  Vector3(double.nan, 0, 0),
  Vector3(0, double.infinity, 0),
  Vector3(0, 0, double.negativeInfinity),
];

void main() {
  group('frame construction', () {
    test('canonical frames have deterministic right-handed axes', () {
      final fixtures = [
        (PlanarFrame.xy(), Vector3(2, 3, 0), Vector3(0, 0, 1)),
        (PlanarFrame.xz(), Vector3(2, 0, 3), Vector3(0, -1, 0)),
        (PlanarFrame.yz(), Vector3(0, 2, 3), Vector3(1, 0, 0)),
      ];
      for (final (frame, world, normal) in fixtures) {
        expectVector3(frame.origin, Vector3.zero());
        expectVector3(frame.localToWorld(Vector2(2, 3)), world);
        expectVector3(frame.normal, normal);
        expectVector3(frame.xAxis.cross(frame.yAxis), normal);
        expect(frame.xAxis.length, closeTo(1, 1e-12));
        expect(frame.yAxis.length, closeTo(1, 1e-12));
        expect(frame.xAxis.dot(frame.yAxis), closeTo(0, 1e-12));
      }
    });

    test('direct axes define a rotated, translated plane', () {
      final angle = math.pi / 3;
      final frame = PlanarFrame(
        origin: Vector3(3, -5, 7),
        xAxis: Vector3(1, 0, 0),
        yAxis: Vector3(0, math.cos(angle), math.sin(angle)),
      );
      expectVector3(
        frame.localToWorld(Vector2(2, 4)),
        Vector3(5, -3, 7 + 2 * math.sqrt(3)),
      );
      expectVector3(frame.normal, Vector3(0, -math.sqrt(3) / 2, 0.5));
    });

    test(
      'arbitrary plane preserves normal and projected preferred direction',
      () {
        final plane = PlaneSurface(
          origin: Vector3(4, 5, 6),
          normal: Vector3(1, 2, 3),
        );
        final preferred = Vector3(2, -1, 4);
        final frame = PlanarFrame.fromPlane(
          plane: plane,
          preferredDirection: preferred,
        );
        final expectedX =
            preferred - plane.normal * preferred.dot(plane.normal);
        expectedX.normalize();
        expectVector3(frame.origin, plane.origin);
        expectVector3(frame.normal, plane.normal);
        expectVector3(frame.xAxis, expectedX);
        expectVector3(frame.xAxis.cross(frame.yAxis), frame.normal);
        expect(frame.xAxis.dot(frame.normal), closeTo(0, 1e-12));
        expect(frame.yAxis.dot(frame.normal), closeTo(0, 1e-12));
        expect(preferred, Vector3(2, -1, 4));
        final repeated = PlanarFrame.fromPlane(
          plane: plane,
          preferredDirection: preferred,
        );
        expect(repeated.xAxis, frame.xAxis);
        expect(repeated.yAxis, frame.yAxis);
      },
    );

    test('reversing plane normal preserves X and reverses Y', () {
      final preferred = Vector3(1, 0, 2);
      final frame = PlanarFrame.fromPlane(
        plane: PlaneSurface(origin: Vector3.zero(), normal: Vector3(0, 0, -5)),
        preferredDirection: preferred,
      );
      expectVector3(frame.xAxis, Vector3(1, 0, 0));
      expectVector3(frame.yAxis, Vector3(0, -1, 0));
      expectVector3(frame.normal, Vector3(0, 0, -1));
    });

    test(
      'direction normalization handles very large and very small magnitudes',
      () {
        final plane = PlaneSurface(
          origin: Vector3.zero(),
          normal: Vector3(0, 0, 1),
        );
        for (final magnitude in [1e308, 1e-308]) {
          final frame = PlanarFrame.fromPlane(
            plane: plane,
            preferredDirection: Vector3(magnitude, magnitude, magnitude),
          );
          expectVector3(
            frame.xAxis,
            Vector3(math.sqrt(0.5), math.sqrt(0.5), 0),
          );
        }
      },
    );

    test('rejects invalid origin and nonorthonormal axes', () {
      for (final origin in invalidVectors) {
        expect(() => PlanarFrame.xy(origin: origin), throwsArgumentError);
      }
      for (final axis in [
        Vector3.zero(),
        Vector3(2, 0, 0),
        Vector3(1e308, 0, 0),
        ...invalidVectors,
      ]) {
        expect(
          () => PlanarFrame(
            origin: Vector3.zero(),
            xAxis: axis,
            yAxis: Vector3(0, 1, 0),
          ),
          throwsArgumentError,
        );
        expect(
          () => PlanarFrame(
            origin: Vector3.zero(),
            xAxis: Vector3(0, 1, 0),
            yAxis: axis,
          ),
          throwsArgumentError,
        );
      }
      for (final y in [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(1, 1, 0)..normalize(),
      ]) {
        expect(
          () => PlanarFrame(
            origin: Vector3.zero(),
            xAxis: Vector3(1, 0, 0),
            yAxis: y,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects unresolved preferred directions using angular tolerance', () {
      final plane = PlaneSurface(
        origin: Vector3.zero(),
        normal: Vector3(0, 0, 1),
      );
      for (final direction in [
        Vector3.zero(),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
        Vector3(1e-12, 0, 1),
        ...invalidVectors,
      ]) {
        expect(
          () => PlanarFrame.fromPlane(
            plane: plane,
            preferredDirection: direction,
          ),
          throwsArgumentError,
        );
      }
      final direction = Vector3(1e-5, 0, 1);
      expect(
        () => PlanarFrame.fromPlane(
          plane: plane,
          preferredDirection: direction,
          tolerance: GeometryTolerance(angular: 1e-4),
        ),
        throwsArgumentError,
      );
      expectVector3(
        PlanarFrame.fromPlane(
          plane: plane,
          preferredDirection: direction,
        ).xAxis,
        Vector3(1, 0, 0),
      );
    });

    test('copies constructor inputs and getter results', () {
      final origin = Vector3(1, 2, 3);
      final x = Vector3(1, 0, 0);
      final y = Vector3(0, 1, 0);
      final frame = PlanarFrame(origin: origin, xAxis: x, yAxis: y);
      origin.setZero();
      x.setZero();
      y.setZero();
      frame.origin.setZero();
      frame.xAxis.setZero();
      frame.yAxis.setZero();
      frame.normal.setZero();
      frame.plane.origin.setZero();
      frame.plane.normal.setZero();
      expectVector3(frame.origin, Vector3(1, 2, 3));
      expectVector3(frame.xAxis, Vector3(1, 0, 0));
      expectVector3(frame.yAxis, Vector3(0, 1, 0));
      expectVector3(frame.normal, Vector3(0, 0, 1));
    });
  });

  group('transforms and plane queries', () {
    test('round trips through all canonical and arbitrary frames', () {
      final origin = Vector3(-3, 7, 11);
      final frames = [
        PlanarFrame.xy(origin: origin),
        PlanarFrame.xz(origin: origin),
        PlanarFrame.yz(origin: origin),
        PlanarFrame.fromPlane(
          plane: PlaneSurface(origin: origin, normal: Vector3(1, 2, 3)),
          preferredDirection: Vector3(2, -1, 4),
        ),
      ];
      for (final frame in frames) {
        for (final local in [
          Vector2.zero(),
          Vector2(1, 2),
          Vector2(-6, 8),
          Vector2(0.125, -0.375),
        ]) {
          final world = frame.localToWorld(local);
          expectVector2(frame.worldToLocal(world), local);
          expectVector3(frame.localToWorld(frame.worldToLocal(world)), world);
          expect(frame.signedDistance(world), closeTo(0, 1e-12));
        }
      }
    });

    test('projection accepts off-plane points while conversion validates', () {
      final frame = PlanarFrame.xz(origin: Vector3(10, 20, 30));
      final point = Vector3(12, 25, 33);
      expect(frame.signedDistance(point), -5);
      expect(frame.containsPoint(point), isFalse);
      expect(() => frame.worldToLocal(point), throwsArgumentError);
      expectVector2(frame.projectToLocal(point), Vector2(2, 3));
      expectVector3(frame.projectPoint(point), Vector3(12, 20, 33));
      expectVector3(
        frame.localToWorld(frame.projectToLocal(point)),
        frame.projectPoint(point),
      );
      expect(point, Vector3(12, 25, 33));
    });

    test('rotated projection and distance follow the oriented plane', () {
      final frame = PlanarFrame.fromPlane(
        plane: PlaneSurface(
          origin: Vector3(3, 4, 5),
          normal: Vector3(0, -1, 1),
        ),
        preferredDirection: Vector3(1, 0, 0),
      );
      final world = frame.localToWorld(Vector2(2, -3));
      for (final offset in [-7.0, 7.0]) {
        final point = world + frame.normal * offset;
        expect(frame.signedDistance(point), closeTo(offset, 1e-12));
        expectVector3(frame.projectPoint(point), world);
        expectVector2(frame.projectToLocal(point), Vector2(2, -3));
      }
    });

    test(
      'distance tolerance is inclusive, configurable and never moves input',
      () {
        final frame = PlanarFrame.xy(
          tolerance: GeometryTolerance(distance: 0.25),
        );
        for (final z in [-0.25, 0.25]) {
          final point = Vector3(1, 2, z);
          expect(frame.containsPoint(point), isTrue);
          expectVector2(frame.worldToLocal(point), Vector2(1, 2));
          expect(point.z, z);
        }
        expect(frame.containsPoint(Vector3(1, 2, 0.250001)), isFalse);
        final exact = PlanarFrame.xy(tolerance: GeometryTolerance(distance: 0));
        expect(exact.containsPoint(Vector3(0, 0, 0)), isTrue);
        expect(exact.containsPoint(Vector3(0, 0, 1e-15)), isFalse);
      },
    );

    test('rejects all nonfinite transformation and query inputs', () {
      final frame = PlanarFrame.xy();
      for (final point in invalidVectors) {
        expect(() => frame.worldToLocal(point), throwsArgumentError);
        expect(() => frame.projectToLocal(point), throwsArgumentError);
        expect(() => frame.projectPoint(point), throwsArgumentError);
        expect(() => frame.signedDistance(point), throwsArgumentError);
        expect(() => frame.containsPoint(point), throwsArgumentError);
      }
      for (final point in [
        Vector2(double.nan, 0),
        Vector2(0, double.infinity),
        Vector2(double.negativeInfinity, 0),
      ]) {
        expect(() => frame.localToWorld(point), throwsArgumentError);
      }
    });

    test('reports finite-input arithmetic overflow explicitly', () {
      final frame = PlanarFrame.xy(origin: Vector3(1e308, 0, 0));
      expect(() => frame.localToWorld(Vector2(1e308, 0)), throwsStateError);
      expect(
        () => frame.projectToLocal(Vector3(-1e308, 0, 0)),
        throwsStateError,
      );
      final diagonal = PlanarFrame.fromPlane(
        plane: PlaneSurface(origin: Vector3.zero(), normal: Vector3(0, 0, 1)),
        preferredDirection: Vector3(1, 1, 0),
      );
      expect(
        () => diagonal.projectToLocal(Vector3(1.7e308, 1.7e308, 0)),
        throwsStateError,
      );
    });

    test('transformation results do not alias caller inputs or frame', () {
      final frame = PlanarFrame.xy(origin: Vector3(1, 2, 3));
      final local = Vector2(4, 5);
      final world = Vector3(5, 7, 3);
      frame.localToWorld(local).setZero();
      frame.worldToLocal(world).setZero();
      frame.projectToLocal(world).setZero();
      frame.projectPoint(world).setZero();
      expect(local, Vector2(4, 5));
      expect(world, Vector3(5, 7, 3));
      expectVector3(frame.origin, Vector3(1, 2, 3));
    });
  });

  group('ray intersection', () {
    test('intersects forward rays independently of direction magnitude', () {
      final frame = PlanarFrame.xy(origin: Vector3(0, 0, 3));
      for (final magnitude in [1.0, 1e308, 1e-308]) {
        expectVector3(
          frame.intersectRay(
            rayOrigin: Vector3(1, 2, 7),
            rayDirection: Vector3(0, 0, -magnitude),
          )!,
          Vector3(1, 2, 3),
        );
        expectVector3(
          frame.intersectRay(
            rayOrigin: Vector3(1, 2, -1),
            rayDirection: Vector3(0, 0, magnitude),
          )!,
          Vector3(1, 2, 3),
        );
      }
    });

    test('finds oblique hits on a translated rotated plane', () {
      final frame = PlanarFrame.fromPlane(
        plane: PlaneSurface(
          origin: Vector3(10, 20, 30),
          normal: Vector3(0, 1, 1),
        ),
        preferredDirection: Vector3(1, 0, 0),
      );
      final origin = Vector3(12, 23, 35);
      final direction = Vector3(2, -1, -3);
      final hit = frame.intersectRay(
        rayOrigin: origin,
        rayDirection: direction,
      )!;
      expectVector3(hit, Vector3(16, 21, 29));
      expect(frame.containsPoint(hit), isTrue);
      hit.setZero();
      expect(origin, Vector3(12, 23, 35));
      expect(direction, Vector3(2, -1, -3));
    });

    test('parallel and coplanar rays have no unique hit', () {
      final frame = PlanarFrame.xy();
      for (final origin in [Vector3(0, 0, 1), Vector3.zero()]) {
        expect(
          frame.intersectRay(rayOrigin: origin, rayDirection: Vector3(1, 0, 0)),
          isNull,
        );
      }
    });

    test(
      'angular tolerance classifies near-parallel rays independent of scale',
      () {
        final frame = PlanarFrame.xy(
          tolerance: GeometryTolerance(angular: 1e-4),
        );
        for (final scale in [1e-200, 1.0, 1e200]) {
          expect(
            frame.intersectRay(
              rayOrigin: Vector3(0, 0, 1),
              rayDirection: Vector3(scale, 0, -1e-5 * scale),
            ),
            isNull,
          );
        }
        expectVector3(
          frame.intersectRay(
            rayOrigin: Vector3(0, 0, 1),
            rayDirection: Vector3(1, 0, -1e-3),
          )!,
          Vector3(1000, 0, 0),
        );
      },
    );

    test('angular threshold is inclusive', () {
      final frame = PlanarFrame.xy(tolerance: GeometryTolerance(angular: 0.6));
      expect(
        frame.intersectRay(
          rayOrigin: Vector3(0, 0, 1),
          rayDirection: Vector3(0.8, 0, -0.6),
        ),
        isNull,
      );
    });

    test('rejects behind-origin hits without tolerance-based clamping', () {
      final frame = PlanarFrame.xy(tolerance: GeometryTolerance(distance: 1));
      for (final height in [1.0, 1e-12]) {
        expect(
          frame.intersectRay(
            rayOrigin: Vector3(0, 0, height),
            rayDirection: Vector3(0, 0, 1),
          ),
          isNull,
        );
        expectVector3(
          frame.intersectRay(
            rayOrigin: Vector3(0, 0, height),
            rayDirection: Vector3(0, 0, -1),
          )!,
          Vector3.zero(),
        );
      }
    });

    test('transverse rays starting on-plane hit at the origin', () {
      final frame = PlanarFrame.xy();
      final origin = Vector3(2, 3, 0);
      for (final direction in [Vector3(0, 0, 1), Vector3(0, 0, -1)]) {
        final hit = frame.intersectRay(
          rayOrigin: origin,
          rayDirection: direction,
        )!;
        expectVector3(hit, origin);
        hit.setZero();
        expect(origin, Vector3(2, 3, 0));
      }
    });

    test('rejects invalid ray inputs including a zero direction', () {
      final frame = PlanarFrame.xy();
      for (final direction in [Vector3.zero(), ...invalidVectors]) {
        expect(
          () => frame.intersectRay(
            rayOrigin: Vector3.zero(),
            rayDirection: direction,
          ),
          throwsArgumentError,
        );
      }
      for (final origin in invalidVectors) {
        expect(
          () => frame.intersectRay(
            rayOrigin: origin,
            rayDirection: Vector3(1, 0, 0),
          ),
          throwsArgumentError,
        );
      }
    });

    test('reports unrepresentable ray intersection explicitly', () {
      final frame = PlanarFrame.xy();
      expect(
        () => frame.intersectRay(
          rayOrigin: Vector3(0, 0, 1e308),
          rayDirection: Vector3(1, 0, -0.1),
        ),
        throwsStateError,
      );
    });
  });
}
