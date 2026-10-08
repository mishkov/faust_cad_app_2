import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class TessellatedFace {
  TessellatedFace(
    this.source,
    List<List<Vector3>> loops,
    List<RenderTriangle> triangles,
  ) : loops = List.unmodifiable(loops.map(List<Vector3>.unmodifiable)),
      triangles = List.unmodifiable(triangles);

  final Face source;
  final List<List<Vector3>> loops;
  final List<RenderTriangle> triangles;
}
