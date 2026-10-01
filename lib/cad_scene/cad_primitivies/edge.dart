import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

class Edge extends CadPrimitive {
  final Vertex begin, end;
  final CadCurve curve;

  new(this.begin, this.end, {required this.curve});
}
