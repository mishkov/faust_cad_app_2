import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('evaluates untrimmed radians and signed axial model lengths', () {
    final surface = CylinderSurface(frame: PlanarFrame.xy(), radius: 2);
    expect(surface.evaluate(0, -7), Vector3(2, 0, -7));
    expect(
      (surface.evaluate(math.pi / 2, 3) - Vector3(0, 2, 3)).length,
      lessThan(1e-12),
    );
    expect(
      (surface.evaluate(-0.4, 100) - surface.evaluate(2 * math.pi - 0.4, 100))
          .length,
      lessThan(1e-12),
    );
    expect(surface.normal(0), Vector3(1, 0, 0));
    expect(
      (surface.normal(math.pi) - Vector3(-1, 0, 0)).length,
      lessThan(1e-12),
    );
  });

  test('arbitrary placement has unit radial normals matching derivatives', () {
    final frame = PlanarFrame.fromPlane(
      plane: PlaneSurface(origin: Vector3(5, -7, 9), normal: Vector3(2, -3, 4)),
      preferredDirection: Vector3(1, 2, 0),
    );
    final surface = CylinderSurface(frame: frame, radius: 3);
    for (final angle in [-3.0, 0.0, 0.7, 8.0]) {
      for (final axial in [-11.0, 0.0, 17.0]) {
        final point = surface.evaluate(angle, axial);
        final delta = point - frame.origin;
        expect(delta.dot(frame.normal), closeTo(axial, 1e-12));
        final radial = delta - frame.normal * axial;
        expect(radial.length, closeTo(3, 1e-12));
        expect(radial.dot(frame.xAxis), closeTo(3 * math.cos(angle), 1e-12));
        expect(radial.dot(frame.yAxis), closeTo(3 * math.sin(angle), 1e-12));
        final normal = surface.normal(angle);
        expect(normal.length, closeTo(1, 1e-12));
        expect(normal.dot(frame.normal), closeTo(0, 1e-12));
        expect(normal.dot(radial), closeTo(3, 1e-12));
        const step = 1e-5;
        final angularDerivative =
            (surface.evaluate(angle + step, axial) -
                surface.evaluate(angle - step, axial)) /
            (2 * step);
        final axialDerivative =
            (surface.evaluate(angle, axial + step) -
                surface.evaluate(angle, axial - step)) /
            (2 * step);
        expect(
          (angularDerivative.cross(axialDerivative).normalized() - normal)
              .length,
          lessThan(1e-9),
        );
      }
    }
  });

  test('frame and vector results cannot mutate the surface', () {
    final origin = Vector3(3, 4, 5);
    final x = Vector3(1, 0, 0);
    final y = Vector3(0, 1, 0);
    final surface = CylinderSurface(
      frame: PlanarFrame(origin: origin, xAxis: x, yAxis: y),
      radius: 2,
    );
    origin.setZero();
    x.setZero();
    y.setZero();
    surface.origin.setZero();
    surface.axis.setZero();
    surface.frame.xAxis.setZero();
    surface.frame.yAxis.setZero();
    surface.normal(0).setZero();
    surface.evaluate(0, 1).setZero();
    expect(surface.evaluate(0, 1), Vector3(5, 4, 6));
  });

  test(
    'rejects invalid radius and parameters and reports numeric overflow',
    () {
      final frame = PlanarFrame.xy();
      for (final radius in [
        0.0,
        -1.0,
        double.infinity,
        double.negativeInfinity,
        double.nan,
      ]) {
        expect(
          () => CylinderSurface(frame: frame, radius: radius),
          throwsArgumentError,
        );
      }
      final surface = CylinderSurface(frame: frame, radius: 1);
      for (final invalid in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => surface.evaluate(invalid, 0), throwsArgumentError);
        expect(() => surface.evaluate(0, invalid), throwsArgumentError);
        expect(() => surface.normal(invalid), throwsArgumentError);
      }
      final huge = CylinderSurface(
        frame: PlanarFrame.xy(origin: Vector3(1e308, 0, 1e308)),
        radius: 1e308,
      );
      expect(() => huge.evaluate(0, 0), throwsStateError);
      expect(() => huge.evaluate(math.pi, 1e308), throwsStateError);
    },
  );
}
