import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class Cube extends CadObject {
  final Vertex centerPosition;
  final double size;

  new({required this.centerPosition, required this.size});

  @override
  List<CadPrimitive> build() {
    final halfSize = size / 2;
    final left = centerPosition.vector.x - halfSize;
    final right = centerPosition.vector.x + halfSize;
    final front = centerPosition.vector.y - halfSize;
    final back = centerPosition.vector.y + halfSize;
    final bottom = centerPosition.vector.z - halfSize;
    final top = centerPosition.vector.z + halfSize;

    final frontBottomLeft = Vertex(Vector3(left, front, bottom));
    final frontBottomRight = Vertex(Vector3(right, front, bottom));
    final backBottomLeft = Vertex(Vector3(left, back, bottom));
    final backBottomRight = Vertex(Vector3(right, back, bottom));
    final frontTopLeft = Vertex(Vector3(left, front, top));
    final frontTopRight = Vertex(Vector3(right, front, top));
    final backTopLeft = Vertex(Vector3(left, back, top));
    final backTopRight = Vertex(Vector3(right, back, top));

    return [
      Edge(frontBottomLeft, frontBottomRight, curve: const LinearCadCurve()),
      Edge(frontBottomRight, backBottomRight, curve: const LinearCadCurve()),
      Edge(backBottomRight, backBottomLeft, curve: const LinearCadCurve()),
      Edge(backBottomLeft, frontBottomLeft, curve: const LinearCadCurve()),
      Edge(frontTopLeft, frontTopRight, curve: const LinearCadCurve()),
      Edge(frontTopRight, backTopRight, curve: const LinearCadCurve()),
      Edge(backTopRight, backTopLeft, curve: const LinearCadCurve()),
      Edge(backTopLeft, frontTopLeft, curve: const LinearCadCurve()),
      Edge(frontBottomLeft, frontTopLeft, curve: const LinearCadCurve()),
      Edge(frontBottomRight, frontTopRight, curve: const LinearCadCurve()),
      Edge(backBottomLeft, backTopLeft, curve: const LinearCadCurve()),
      Edge(backBottomRight, backTopRight, curve: const LinearCadCurve()),
    ];
  }
}
