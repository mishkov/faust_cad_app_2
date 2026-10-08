import 'package:vector_math/vector_math_64.dart' show Vector3;

// Internal shared validation for surface and frame arithmetic.
void requireFiniteVector3(Vector3 value, String name) {
  if (!value.x.isFinite || !value.y.isFinite || !value.z.isFinite) {
    throw ArgumentError.value(value, name, 'Must be finite');
  }
}

Vector3 normalizedVector3(Vector3 value, String name) {
  requireFiniteVector3(value, name);
  var scale = value.x.abs();
  if (value.y.abs() > scale) scale = value.y.abs();
  if (value.z.abs() > scale) scale = value.z.abs();
  if (scale == 0) {
    throw ArgumentError.value(value, name, 'Must be nonzero');
  }
  // Divide components individually: multiplying by 1 / scale could overflow.
  return Vector3(value.x / scale, value.y / scale, value.z / scale)
    ..normalize();
}

Vector3 finiteVector3Result(Vector3 value) {
  if (!value.x.isFinite || !value.y.isFinite || !value.z.isFinite) {
    throw StateError('Geometry calculation exceeds finite numeric range');
  }
  return value;
}

double finiteScalarResult(double value) {
  if (!value.isFinite) {
    throw StateError('Geometry calculation exceeds finite numeric range');
  }
  return value;
}
