import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/line3d.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

class GroundGrid extends CadObject {
  final double width;
  final double length;

  GroundGrid([this.width = 100, this.length = 100]);

  @override
  List<CadPrimitive> build() {
    return [
      for (int i = 0; i < 11; i++)
        Line3d(Vertex(i / 10 * width, 0, 0), Vertex(i / 10 * width, length, 0)),
      for (int i = 0; i < 11; i++)
        Line3d(
          Vertex(0, i / 10 * length, 0),
          Vertex(width, i / 10 * length, 0),
        ),
    ];
  }
}
