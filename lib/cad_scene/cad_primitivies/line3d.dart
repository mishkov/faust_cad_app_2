import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/point3d.dart';

class Line3d extends CadPrimitive {
  final Point3d begin, end;

  new(this.begin, this.end);
}
