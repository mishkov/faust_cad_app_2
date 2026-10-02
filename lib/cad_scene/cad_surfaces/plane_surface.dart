import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// An infinite plane through [origin], perpendicular to the unit [normal].
///
/// Face boundaries determine the visible region; they are not stored here.
class PlaneSurface extends CadSurface {
  final Vector3 _origin;
  final Vector3 _normal;

  new({required Vector3 origin, required Vector3 normal})
    : _origin = origin.clone(),
      _normal = normal.clone() {
    if (!origin.x.isFinite || !origin.y.isFinite || !origin.z.isFinite) {
      throw ArgumentError.value(origin, 'origin', 'Must be finite');
    }
    // Scale before normalizing to avoid overflow for large finite normals.
    final scale = normal.x.abs() > normal.y.abs()
        ? normal.x.abs()
        : normal.y.abs();
    final maxComponent = scale > normal.z.abs() ? scale : normal.z.abs();
    if (!normal.x.isFinite ||
        !normal.y.isFinite ||
        !normal.z.isFinite ||
        maxComponent == 0) {
      throw ArgumentError.value(normal, 'normal', 'Must be finite and nonzero');
    }
    _normal.setValues(
      normal.x / maxComponent,
      normal.y / maxComponent,
      normal.z / maxComponent,
    );
    _normal.normalize();
  }

  /// A point on the plane. Returned as a copy to preserve the surface geometry.
  Vector3 get origin => _origin.clone();

  /// The unit normal. Returned as a copy to preserve the surface geometry.
  Vector3 get normal => _normal.clone();
}
