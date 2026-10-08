import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/geometry_tolerance.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

/// An orthonormal, right-handed coordinate frame on an infinite plane.
///
/// Local coordinates use [xAxis] and [yAxis], with [normal] = xAxis × yAxis.
/// All vector inputs are copied and vector getters return defensive copies.
/// Operations throw [ArgumentError] for nonfinite or otherwise invalid inputs,
/// and [StateError] when arithmetic exceeds finite numeric range.
class PlanarFrame {
  final PlaneSurface _plane;
  final Vector3 _xAxis;
  final Vector3 _yAxis;

  /// Creates a frame from finite, unit, perpendicular axes and an [origin].
  ///
  /// Rejects zero, nonunit, or nonperpendicular axes using [tolerance]'s angular
  /// threshold. Accepted roundoff is removed by orthonormalization.
  factory PlanarFrame({
    required Vector3 origin,
    required Vector3 xAxis,
    required Vector3 yAxis,
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) {
    requireFiniteVector3(xAxis, 'xAxis');
    requireFiniteVector3(yAxis, 'yAxis');
    for (final axis in [xAxis, yAxis]) {
      if (!axis.length.isFinite ||
          (axis.length - 1).abs() > tolerance.angular) {
        throw ArgumentError.value(axis, 'axes', 'Must have unit length');
      }
    }
    final x = normalizedVector3(xAxis, 'xAxis');
    final y = normalizedVector3(yAxis, 'yAxis');
    if (x.dot(y).abs() > tolerance.angular) {
      throw ArgumentError('Axes must be perpendicular');
    }
    final plane = PlaneSurface(origin: origin, normal: x.cross(y));
    return PlanarFrame._(
      plane,
      x,
      plane.normal.cross(x)..normalize(),
      tolerance,
    );
  }

  PlanarFrame._(this._plane, this._xAxis, this._yAxis, this.tolerance);

  /// Creates an XY frame with local axes +X/+Y and normal +Z.
  factory PlanarFrame.xy({
    Vector3? origin,
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) => PlanarFrame(
    origin: origin ?? Vector3.zero(),
    xAxis: Vector3(1, 0, 0),
    yAxis: Vector3(0, 1, 0),
    tolerance: tolerance,
  );

  /// Creates an XZ frame with local axes +X/+Z and normal -Y.
  factory PlanarFrame.xz({
    Vector3? origin,
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) => PlanarFrame(
    origin: origin ?? Vector3.zero(),
    xAxis: Vector3(1, 0, 0),
    yAxis: Vector3(0, 0, 1),
    tolerance: tolerance,
  );

  /// Creates a YZ frame with local axes +Y/+Z and normal +X.
  factory PlanarFrame.yz({
    Vector3? origin,
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) => PlanarFrame(
    origin: origin ?? Vector3.zero(),
    xAxis: Vector3(0, 1, 0),
    yAxis: Vector3(0, 0, 1),
    tolerance: tolerance,
  );

  /// Creates a frame preserving [plane]'s origin and oriented normal.
  ///
  /// Local X follows the projection of [preferredDirection] onto [plane].
  /// The direction need not be unit or exactly in-plane. Rejects zero,
  /// nonfinite, or nearly normal directions using [tolerance]'s angular
  /// threshold; no arbitrary fallback axis is chosen.
  factory PlanarFrame.fromPlane({
    required PlaneSurface plane,
    required Vector3 preferredDirection,
    GeometryTolerance tolerance = GeometryTolerance.defaults,
  }) {
    final direction = normalizedVector3(
      preferredDirection,
      'preferredDirection',
    );
    final normal = plane.normal;
    final y = normal.cross(direction);
    if (y.length <= tolerance.angular) {
      throw ArgumentError.value(
        preferredDirection,
        'preferredDirection',
        'Must have a resolvable in-plane direction',
      );
    }
    y.normalize();
    final x = normal.cross(y)..negate();
    x.normalize();
    return PlanarFrame._(
      PlaneSurface(origin: plane.origin, normal: normal),
      x,
      y,
      tolerance,
    );
  }

  /// The model-space numerical policy for this frame.
  final GeometryTolerance tolerance;

  /// The frame origin, returned as a defensive copy.
  Vector3 get origin => _plane.origin;

  /// The local X unit axis, returned as a defensive copy.
  Vector3 get xAxis => _xAxis.clone();

  /// The local Y unit axis, returned as a defensive copy.
  Vector3 get yAxis => _yAxis.clone();

  /// The right-handed unit normal, returned as a defensive copy.
  Vector3 get normal => _plane.normal;

  /// The immutable underlying plane geometry.
  PlaneSurface get plane => _plane;

  /// Converts a finite local 2D [point] to a new world 3D point on the plane.
  Vector3 localToWorld(Vector2 point) {
    if (!point.x.isFinite || !point.y.isFinite) {
      throw ArgumentError.value(point, 'point', 'Must be finite');
    }
    return finiteVector3Result(origin + _xAxis * point.x + _yAxis * point.y);
  }

  /// Converts a world [point] after validating plane membership.
  ///
  /// Throws [ArgumentError] if [point] is farther from the plane than
  /// [tolerance]'s distance. Accepted normal residuals are discarded.
  /// Use [projectToLocal] for intentional projection of off-plane points.
  Vector2 worldToLocal(Vector3 point) {
    if (!containsPoint(point)) {
      throw ArgumentError.value(point, 'point', 'Must lie on the plane');
    }
    return projectToLocal(point);
  }

  /// Projects a finite world [point] to local 2D without membership validation.
  ///
  /// The normal component is deliberately discarded; [point] is not modified.
  Vector2 projectToLocal(Vector3 point) {
    requireFiniteVector3(point, 'point');
    final delta = finiteVector3Result(point - origin);
    return Vector2(
      finiteScalarResult(_xAxis.dot(delta)),
      finiteScalarResult(_yAxis.dot(delta)),
    );
  }

  /// Orthogonally projects [point] to a new world point on the plane.
  Vector3 projectPoint(Vector3 point) => _plane.projectPoint(point);

  /// Returns signed distance to [point], positive along [normal], in model units.
  double signedDistance(Vector3 point) => _plane.signedDistance(point);

  /// Tests plane membership using the inclusive [tolerance] distance threshold.
  bool containsPoint(Vector3 point) =>
      _plane.containsPoint(point, tolerance: tolerance);

  /// Intersects the forward ray from [rayOrigin] along [rayDirection].
  ///
  /// Returns a new world point or `null` for parallel rays (including coplanar
  /// rays with no unique hit) and intersections behind the origin. A transverse
  /// ray starting exactly on the plane hits at its origin. Direction magnitude
  /// does not affect classification; finite nonzero directions are normalized.
  /// Parallelism uses [tolerance]'s angular threshold. Distance tolerance never
  /// moves a ray origin onto the plane or accepts a hit behind it.
  Vector3? intersectRay({
    required Vector3 rayOrigin,
    required Vector3 rayDirection,
  }) {
    requireFiniteVector3(rayOrigin, 'rayOrigin');
    final direction = normalizedVector3(rayDirection, 'rayDirection');
    final denominator = normal.dot(direction);
    if (denominator.abs() <= tolerance.angular) return null;
    final distance = finiteScalarResult(
      -signedDistance(rayOrigin) / denominator,
    );
    if (distance < 0) return null;
    return finiteVector3Result(rayOrigin + direction * distance);
  }
}
