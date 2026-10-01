import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class Vertex extends CadPrimitive {
  final Vector3 vector;

  new(this.vector);
}
