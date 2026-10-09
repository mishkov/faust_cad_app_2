import '../cad_scene/cad_primitivies/cad_primitive.dart';
import '../cad_scene/cad_primitivies/face.dart';
import 'output_reference.dart';

// A consumer-owned topology snapshot with explicit semantic correspondence.
final class EvaluatedGeometry {
  EvaluatedGeometry({
    required List<CadPrimitive> geometry,
    required Map<CadPrimitive, OutputReference> bodies,
    required Map<Face, OutputReference> faces,
  }) : geometry = List.unmodifiable(geometry),
       bodies = Map.unmodifiable(bodies),
       faces = Map.unmodifiable(faces);

  final List<CadPrimitive> geometry;
  final Map<CadPrimitive, OutputReference> bodies;
  final Map<Face, OutputReference> faces;
}
