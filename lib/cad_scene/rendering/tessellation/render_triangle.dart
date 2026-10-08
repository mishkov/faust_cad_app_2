import 'package:vector_math/vector_math_64.dart' show Vector3;

/// Derived render data only; never inserted into CAD topology.
class RenderTriangle {
  RenderTriangle(List<Vector3> points, List<Vector3> normals)
    : points = List.unmodifiable(points),
      normals = List.unmodifiable(normals);

  final List<Vector3> points;
  final List<Vector3> normals;
}
