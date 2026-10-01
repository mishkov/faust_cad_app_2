import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/line3d.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';

class Cube extends CadObject {
  final Vertex centerPosition;
  final double size;

  new({required this.centerPosition, required this.size});

  @override
  List<CadPrimitive> build() {
    final halfSize = size / 2;
    final left = centerPosition.x - halfSize;
    final right = centerPosition.x + halfSize;
    final front = centerPosition.y - halfSize;
    final back = centerPosition.y + halfSize;
    final bottom = centerPosition.z - halfSize;
    final top = centerPosition.z + halfSize;

    final frontBottomLeft = Vertex(left, front, bottom);
    final frontBottomRight = Vertex(right, front, bottom);
    final backBottomLeft = Vertex(left, back, bottom);
    final backBottomRight = Vertex(right, back, bottom);
    final frontTopLeft = Vertex(left, front, top);
    final frontTopRight = Vertex(right, front, top);
    final backTopLeft = Vertex(left, back, top);
    final backTopRight = Vertex(right, back, top);

    return [
      Line3d(frontBottomLeft, frontBottomRight),
      Line3d(frontBottomRight, backBottomRight),
      Line3d(backBottomRight, backBottomLeft),
      Line3d(backBottomLeft, frontBottomLeft),
      Line3d(frontTopLeft, frontTopRight),
      Line3d(frontTopRight, backTopRight),
      Line3d(backTopRight, backTopLeft),
      Line3d(backTopLeft, frontTopLeft),
      Line3d(frontBottomLeft, frontTopLeft),
      Line3d(frontBottomRight, frontTopRight),
      Line3d(backBottomLeft, backTopLeft),
      Line3d(backBottomRight, backTopRight),
    ];
  }
}
