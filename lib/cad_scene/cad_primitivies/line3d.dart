import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

class Line3d extends CadPrimitive {
  final Vertex begin, end;

  new(this.begin, this.end);
}
