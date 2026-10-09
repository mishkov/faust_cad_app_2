import '../cad_scene/cad_primitivies/cad_primitive.dart';
import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/cad_primitivies/solid.dart';
import '../cad_scene/cad_surfaces/plane_surface.dart';
import 'output_reference.dart';
import 'topology_copy.dart';

final class FeatureOutput {
  FeatureOutput({
    required this.key,
    required this.kind,
    required CadPrimitive geometry,
  }) : _geometry = TopologyCopy().copy(geometry) {
    if (key.isEmpty) throw ArgumentError('Output key must not be empty');
    if (kind == OutputKind.body && geometry is! Solid ||
        kind == OutputKind.planarFace &&
            (geometry is! Face || geometry.surface is! PlaneSurface)) {
      throw ArgumentError('Geometry must match its semantic output kind');
    }
  }

  final String key;
  final OutputKind kind;
  final CadPrimitive _geometry;

  // Each consumer owns its copy, including mutable legacy Vertex vectors.
  CadPrimitive get geometry => TopologyCopy().copy(_geometry);
}
