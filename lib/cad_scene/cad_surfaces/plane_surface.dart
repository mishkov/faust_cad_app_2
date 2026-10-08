import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// An infinite plane through [origin], perpendicular to the unit [normal].
///
/// Face boundaries determine the visible region; they are not stored here.
class PlaneSurface extends CadSurface {
  final Vector3 _origin;
  final Vector3 _normal;

  /// Creates a plane from a finite [origin] and finite, nonzero [normal].
  ///
  /// Copies both inputs and normalizes [normal] without modifying caller data.
  /// Throws [ArgumentError] for invalid inputs.
  PlaneSurface({required Vector3 origin, required Vector3 normal})
    : _origin = origin.clone(),
      _normal = normalizedVector3(normal, 'normal') {
    requireFiniteVector3(origin, 'origin');
  }

  /// A point on the plane, returned as a defensive copy.
  Vector3 get origin => _origin.clone();

  /// The unit normal, returned as a defensive copy.
  Vector3 get normal => _normal.clone();

  /// Returns the signed distance to [point], in model length units.
  ///
  /// Positive distances lie on the [normal] side. Throws [ArgumentError] for
  /// nonfinite input and [StateError] if arithmetic exceeds finite range.
  double signedDistance(Vector3 point) {
    requireFiniteVector3(point, 'point');
    final delta = finiteVector3Result(point - _origin);
    return finiteScalarResult(_normal.dot(delta));
  }

  /// Tests whether [point] lies within [tolerance]'s distance of the plane.
  ///
  /// The comparison is inclusive and does not move [point]. Input and numeric
  /// range errors follow [signedDistance].
  bool containsPoint(
    Vector3 point, {
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) => signedDistance(point).abs() <= tolerance.distance;

  /// Orthogonally projects [point] onto the plane, returning a new vector.
  ///
  /// Off-plane points are accepted; use [containsPoint] to validate membership.
  /// Input and numeric range errors follow [signedDistance].
  Vector3 projectPoint(Vector3 point) =>
      finiteVector3Result(point - _normal * signedDistance(point));
}
