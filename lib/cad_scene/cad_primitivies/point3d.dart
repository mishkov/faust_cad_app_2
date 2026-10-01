import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';

class Point3d extends CadPrimitive {
  final double x, y, z;

  new(this.x, this.y, this.z);

  Point3d operator -(Point3d other) =>
      Point3d(x - other.x, y - other.y, z - other.z);
}
