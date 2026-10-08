import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default and configured thresholds retain their separate units', () {
    expect(GeometryTolerance.defaults.distance, 1e-8);
    expect(GeometryTolerance.defaults.angular, 1e-10);
    final tolerance = GeometryTolerance(distance: 0.002, angular: 1e-6);
    expect(tolerance.distance, 0.002);
    expect(tolerance.angular, 1e-6);
    expect(GeometryTolerance(distance: 0).distance, 0);
  });

  test('rejects invalid distance thresholds', () {
    for (final value in [
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => GeometryTolerance(distance: value), throwsArgumentError);
    }
  });

  test('rejects invalid angular thresholds', () {
    for (final value in [
      0.0,
      -1.0,
      1.0,
      2.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(() => GeometryTolerance(angular: value), throwsArgumentError);
    }
  });
}
