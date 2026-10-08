import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  late CircularCadCurve circle;
  late Vertex a;
  late Vertex b;

  setUp(() {
    circle = CircularCadCurve(frame: PlanarFrame.xy(), radius: 2);
    a = Vertex(circle.evaluate(0));
    b = Vertex(circle.evaluate(math.pi / 2));
  });

  Edge arc(double sweep) => Edge(
    a,
    b,
    curve: circle,
    trim: CircularTrim(startAngle: 0, sweepAngle: sweep),
  );

  test('opposite tiny sweeps remain distinct within endpoint tolerance', () {
    const sweep = 1e-12;
    final end = Vertex(circle.evaluate(sweep));
    final ccw = Edge(
      a,
      end,
      curve: circle,
      trim: CircularTrim(startAngle: 0, sweepAngle: sweep),
    );
    final cw = Edge(
      a,
      end,
      curve: circle,
      trim: CircularTrim(startAngle: 0, sweepAngle: -sweep),
    );
    expect(ccw.hasSameBoundary(cw), isFalse);
    expect(ccw.hasSameBoundary(cw.reversed()), isFalse);
    expect(ccw.hasSameBoundary(ccw.reversed()), isTrue);
  });

  test('signed trim distinguishes minor and complementary major arcs', () {
    final minor = arc(math.pi / 2);
    final major = arc(-3 * math.pi / 2);
    expect(minor.begin, same(major.begin));
    expect(minor.end, same(major.end));
    expect(minor.hasSameBoundary(major), isFalse);
    expect(minor.hasSameBoundary(major.reversed()), isFalse);
    expect(
      (minor.evaluate(0.5) - Vector3(math.sqrt(2), math.sqrt(2), 0)).length,
      lessThan(1e-12),
    );
    expect(
      (major.evaluate(0.5) - Vector3(-math.sqrt(2), -math.sqrt(2), 0)).length,
      lessThan(1e-12),
    );
    expect(minor.tangent(0), Vector3(0, math.pi, 0));
    expect(major.tangent(0), Vector3(0, -3 * math.pi, 0));
  });

  test(
    'reversal preserves geometry, shared vertices, and directed derivatives',
    () {
      for (final original in [arc(math.pi / 2), arc(-3 * math.pi / 2)]) {
        final reverse = original.reversed();
        expect(reverse.curve, same(original.curve));
        expect(reverse.begin, same(original.end));
        expect(reverse.end, same(original.begin));
        expect(reverse.trim!.sweepAngle, -original.trim!.sweepAngle);
        expect(original.hasSameBoundary(reverse), isTrue);
        expect(reverse.hasSameBoundary(original), isTrue);
        expect(original.hasSameBoundary(reverse.reversed()), isTrue);
        for (final t in [0.0, 0.2, 0.5, 1.0]) {
          expect(
            (reverse.evaluate(t) - original.evaluate(1 - t)).length,
            lessThan(1e-12),
          );
          expect(
            (reverse.tangent(t) + original.tangent(1 - t)).length,
            lessThan(1e-12),
          );
        }
      }
    },
  );

  test('angles across the periodic origin retain the intended arc', () {
    final start = 7 * math.pi / 4;
    final edge = Edge(
      Vertex(circle.evaluate(start)),
      Vertex(circle.evaluate(math.pi / 4)),
      curve: circle,
      trim: CircularTrim(startAngle: start, sweepAngle: math.pi / 2),
    );
    expect((edge.evaluate(0.5) - Vector3(2, 0, 0)).length, lessThan(1e-12));
    expect(edge.hasSameBoundary(edge.reversed()), isTrue);
    final shifted = Edge(
      edge.begin,
      edge.end,
      curve: circle,
      trim: CircularTrim(
        startAngle: start - 2 * math.pi,
        sweepAngle: math.pi / 2,
      ),
    );
    expect(edge.hasSameBoundary(shifted), isTrue);
  });

  test('full circles use multiple exact arcs with shared topology', () {
    for (final count in [2, 3, 4, 8]) {
      for (final clockwise in [false, true]) {
        final wire = Wire.circular(
          circle,
          arcCount: count,
          clockwise: clockwise,
          startAngle: 0.3,
        );
        expect(wire.isClosed, isTrue);
        expect(wire.edges, hasLength(count));
        expect(wire.reversed().isClosed, isTrue);
        for (var i = 0; i < count; i++) {
          final edge = wire.edges[i];
          expect(edge.curve, same(circle));
          expect(edge.end, same(wire.edges[(i + 1) % count].begin));
          expect(edge.begin, isNot(same(edge.end)));
          expect(edge.hasValidCircularEndpoints, isTrue);
          expect(
            (edge.evaluate(0.5) - circle.center).length,
            closeTo(2, 1e-12),
          );
          expect(
            edge.trim!.sweepAngle,
            closeTo((clockwise ? -1 : 1) * 2 * math.pi / count, 1e-12),
          );
        }
      }
    }
    expect(() => Wire.circular(circle, arcCount: 1), throwsArgumentError);
    expect(() => Wire.circular(circle, arcCount: 0), throwsArgumentError);
  });

  test(
    'rejects invalid trims, single-edge circles, and incorrect endpoints',
    () {
      for (final sweep in [
        0.0,
        2 * math.pi,
        -2 * math.pi,
        3 * math.pi,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => CircularTrim(startAngle: 0, sweepAngle: sweep),
          throwsArgumentError,
        );
      }
      for (final start in [double.nan, double.infinity]) {
        expect(
          () => CircularTrim(startAngle: start, sweepAngle: 1),
          throwsArgumentError,
        );
      }
      final trim = CircularTrim(startAngle: 0, sweepAngle: math.pi / 2);
      expect(() => Edge(a, b, curve: circle), throwsArgumentError);
      expect(
        () => Edge(a, b, curve: const LinearCadCurve(), trim: trim),
        throwsArgumentError,
      );
      expect(() => Edge(a, a, curve: circle, trim: trim), throwsArgumentError);
      expect(
        () => Edge(a, Vertex(a.vector.clone()), curve: circle, trim: trim),
        throwsArgumentError,
      );
      expect(() => Edge(b, a, curve: circle, trim: trim), throwsArgumentError);
      expect(() => arc(math.pi), throwsArgumentError);
      expect(
        () => Edge(a, Vertex(Vector3(0, 2, 0.1)), curve: circle, trim: trim),
        throwsArgumentError,
      );
      expect(
        () => Edge(a, Vertex(Vector3(0, 3, 0)), curve: circle, trim: trim),
        throwsArgumentError,
      );
      expect(
        () => Edge(
          Vertex(Vector3(double.nan, 0, 0)),
          b,
          curve: circle,
          trim: trim,
        ),
        throwsArgumentError,
      );
      for (final t in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(() => arc(math.pi / 2).evaluate(t), throwsArgumentError);
        expect(() => arc(math.pi / 2).tangent(t), throwsArgumentError);
      }
    },
  );

  test(
    'endpoint agreement uses model tolerance without snapping or merging',
    () {
      final tolerant = CircularCadCurve(
        frame: PlanarFrame.xy(tolerance: GeometryTolerance(distance: 0.001)),
        radius: 2,
      );
      final end = Vertex(
        tolerant.evaluate(math.pi / 2) + Vector3(0, 0, 0.0005),
      );
      final edge = Edge(
        a,
        end,
        curve: tolerant,
        trim: CircularTrim(startAngle: 0, sweepAngle: math.pi / 2),
      );
      expect(edge.end, same(end));
      expect(end.vector.z, 0.0005);
      expect(edge.evaluate(1).z, 0);
      final duplicate = Edge(
        Vertex(a.vector.clone()),
        end,
        curve: tolerant,
        trim: edge.trim,
      );
      expect(edge.hasSameBoundary(duplicate), isFalse);
    },
  );

  test('linear edges retain endpoint evaluation and reversal', () {
    final edge = Edge(a, b, curve: const LinearCadCurve());
    expect(edge.evaluate(0), a.vector);
    expect(edge.evaluate(1), b.vector);
    expect(edge.evaluate(0.5), (a.vector + b.vector) / 2);
    expect(edge.tangent(0.5), b.vector - a.vector);
    expect(edge.reversed().hasSameBoundary(edge), isTrue);
  });
}
