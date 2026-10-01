import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';

class Vertex extends CadPrimitive {
  final double x, y, z;

  new(this.x, this.y, this.z);

  Vertex operator -(Vertex other) =>
      Vertex(x - other.x, y - other.y, z - other.z);
}
