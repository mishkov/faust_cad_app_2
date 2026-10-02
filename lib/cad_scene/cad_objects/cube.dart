import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class Cube extends CadObject {
  final Vertex centerPosition;
  final double size;

  new({required this.centerPosition, required this.size});

  @override
  List<Solid> build() {
    final halfSize = size / 2;
    final left = centerPosition.vector.x - halfSize;
    final right = centerPosition.vector.x + halfSize;
    final front = centerPosition.vector.y - halfSize;
    final back = centerPosition.vector.y + halfSize;
    final bottom = centerPosition.vector.z - halfSize;
    final top = centerPosition.vector.z + halfSize;

    final frontBottomLeft = Vertex(Vector3(left, front, bottom));
    final frontBottomRight = Vertex(Vector3(right, front, bottom));
    final backBottomLeft = Vertex(Vector3(left, back, bottom));
    final backBottomRight = Vertex(Vector3(right, back, bottom));
    final frontTopLeft = Vertex(Vector3(left, front, top));
    final frontTopRight = Vertex(Vector3(right, front, top));
    final backTopLeft = Vertex(Vector3(left, back, top));
    final backTopRight = Vertex(Vector3(right, back, top));

    return [
      Solid(
        shells: [
          Shell(
            faces: [
              // Counterclockwise boundaries viewed from outside the cube.
              _buildFace([
                frontBottomLeft,
                frontBottomRight,
                frontTopRight,
                frontTopLeft,
              ]),
              _buildFace([
                backBottomRight,
                backBottomLeft,
                backTopLeft,
                backTopRight,
              ]),
              _buildFace([
                frontBottomLeft,
                backBottomLeft,
                backBottomRight,
                frontBottomRight,
              ]),
              _buildFace([
                frontTopLeft,
                frontTopRight,
                backTopRight,
                backTopLeft,
              ]),
              _buildFace([
                backBottomLeft,
                frontBottomLeft,
                frontTopLeft,
                backTopLeft,
              ]),
              _buildFace([
                frontBottomRight,
                backBottomRight,
                backTopRight,
                frontTopRight,
              ]),
            ],
          ),
        ],
      ),
    ];
  }

  Face _buildFace(List<Vertex> vertices) => Face(
    surface: PlaneSurface(
      origin: vertices.first.vector,
      normal: (vertices[1].vector - vertices[0].vector).cross(
        vertices[2].vector - vertices[0].vector,
      ),
    ),
    outerWire: Wire([
      for (var i = 0; i < vertices.length; i++)
        Edge(
          vertices[i],
          vertices[(i + 1) % vertices.length],
          curve: const LinearCadCurve(),
        ),
    ]),
  );
}
