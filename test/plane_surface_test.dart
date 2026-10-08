import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('plane queries distinguish projection from membership', () {
    final plane = PlaneSurface(
      origin: Vector3(1, 2, 3),
      normal: Vector3(0, 0, -2),
    );
    final point = Vector3(4, 5, 8);
    expect(plane.signedDistance(point), -5);
    expect(plane.containsPoint(point), isFalse);
    expect(
      plane.containsPoint(point, tolerance: GeometryTolerance(distance: 5)),
      isTrue,
    );
    expect(plane.projectPoint(point), Vector3(4, 5, 3));
    expect(point, Vector3(4, 5, 8));
    expect(plane.containsPoint(plane.projectPoint(point)), isTrue);
  });

  test('plane queries reject nonfinite points and numeric overflow', () {
    final plane = PlaneSurface(
      origin: Vector3.zero(),
      normal: Vector3(1, 1, 1),
    );
    for (final point in [
      Vector3(double.nan, 0, 0),
      Vector3(0, double.infinity, 0),
      Vector3(0, 0, double.negativeInfinity),
    ]) {
      expect(() => plane.signedDistance(point), throwsArgumentError);
      expect(() => plane.containsPoint(point), throwsArgumentError);
      expect(() => plane.projectPoint(point), throwsArgumentError);
    }
    expect(() => plane.signedDistance(Vector3.all(1.7e308)), throwsStateError);
  });

  test('plane retains its origin and normalizes its normal', () {
    final origin = Vector3(1, 2, 3);
    final normal = Vector3(0, 0, 2);
    final surface = PlaneSurface(origin: origin, normal: normal);

    expect(surface, isA<CadSurface>());
    expect(surface.origin, origin);
    expect(surface.normal, Vector3(0, 0, 1));
    expect(normal, Vector3(0, 0, 2));

    origin.setZero();
    normal.setZero();
    surface.origin.setZero();
    surface.normal.setZero();

    expect(surface.origin, Vector3(1, 2, 3));
    expect(surface.normal, Vector3(0, 0, 1));
  });

  test('normalization accepts very large or small finite normals', () {
    for (final magnitude in [1e308, 1e-308]) {
      final surface = PlaneSurface(
        origin: Vector3.zero(),
        normal: Vector3(magnitude, magnitude, magnitude),
      );
      expect(surface.normal.length, closeTo(1, 1e-12));
      expect(surface.normal.x, greaterThan(0));
    }
  });

  test('rejects zero or nonfinite normals', () {
    for (final normal in [
      Vector3.zero(),
      Vector3(double.nan, 0, 1),
      Vector3(0, double.infinity, 1),
      Vector3(0, 1, double.negativeInfinity),
    ]) {
      expect(
        () => PlaneSurface(origin: Vector3.zero(), normal: normal),
        throwsArgumentError,
      );
    }
  });

  test('rejects nonfinite origins', () {
    for (final origin in [
      Vector3(double.nan, 0, 0),
      Vector3(0, double.infinity, 0),
      Vector3(0, 0, double.negativeInfinity),
    ]) {
      expect(
        () => PlaneSurface(origin: origin, normal: Vector3(0, 0, 1)),
        throwsArgumentError,
      );
    }
  });
}
