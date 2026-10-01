import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';

abstract class CadObject {
  List<CadPrimitive> build();
}
