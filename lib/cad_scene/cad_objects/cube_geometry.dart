import '../cad_primitivies/face.dart';
import '../cad_primitivies/solid.dart';

// Names are assigned by the builder, independently of face list order.
final class CubeGeometry {
  CubeGeometry({required this.body, required Map<String, Face> planarFaces})
    : planarFaces = Map.unmodifiable(planarFaces);
  final Solid body;
  final Map<String, Face> planarFaces;
}
