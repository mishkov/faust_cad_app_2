import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('analytic circle follows its translated, tilted frame', () {
    final circle = CircularCadCurve(
      frame: PlanarFrame.yz(origin: Vector3(3, 4, 5)),
      radius: 2,
    );
    expect(circle.center, Vector3(3, 4, 5));
    expect(circle.evaluate(0), Vector3(3, 6, 5));
    expect(
      (circle.evaluate(math.pi / 2) - Vector3(3, 4, 7)).length,
      lessThan(1e-12),
    );
    expect(circle.tangent(0), Vector3(0, 0, 2));
    expect(
      (circle.tangent(math.pi / 2) - Vector3(0, -2, 0)).length,
      lessThan(1e-12),
    );
    expect(
      (circle.evaluate(-math.pi / 2) - circle.evaluate(3 * math.pi / 2)).length,
      lessThan(1e-12),
    );
    final step = 1e-6;
    final derivative =
        (circle.evaluate(0.7 + step) - circle.evaluate(0.7 - step)) /
        (2 * step);
    expect((derivative - circle.tangent(0.7)).length, lessThan(1e-8));
  });

  test('returned center and evaluated points do not mutate geometry', () {
    final circle = CircularCadCurve(frame: PlanarFrame.xy(), radius: 2);
    circle.center.setZero();
    circle.evaluate(0).setZero();
    circle.frame.xAxis.setZero();
    expect(circle.evaluate(0), Vector3(2, 0, 0));
  });

  test('rejects nonpositive and nonfinite radii and parameters', () {
    final frame = PlanarFrame.xy();
    for (final radius in [0.0, -1.0, double.infinity, double.nan]) {
      expect(
        () => CircularCadCurve(frame: frame, radius: radius),
        throwsArgumentError,
      );
    }
    final circle = CircularCadCurve(frame: frame, radius: 1);
    for (final angle in [
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      expect(() => circle.evaluate(angle), throwsArgumentError);
      expect(() => circle.tangent(angle), throwsArgumentError);
    }
  });
}
