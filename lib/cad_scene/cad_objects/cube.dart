import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/line3d.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/point3d.dart';

class Cube extends CadObject {
  final Point3d centerPosition;
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

    final frontBottomLeft = Point3d(left, front, bottom);
    final frontBottomRight = Point3d(right, front, bottom);
    final backBottomLeft = Point3d(left, back, bottom);
    final backBottomRight = Point3d(right, back, bottom);
    final frontTopLeft = Point3d(left, front, top);
    final frontTopRight = Point3d(right, front, top);
    final backTopLeft = Point3d(left, back, top);
    final backTopRight = Point3d(right, back, top);

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
