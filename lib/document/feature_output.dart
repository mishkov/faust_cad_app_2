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
    Map<String, Face> faceKeys = const {},
  }) {
    final copy = TopologyCopy();
    _geometry = copy.copy(geometry);
    final bodyFaces = geometry is Solid
        ? geometry.shells.expand((s) => s.faces).toSet()
        : <Face>{};
    if (faceKeys.values.toSet().length != faceKeys.length ||
        faceKeys.keys.any((k) => k.isEmpty) ||
        faceKeys.values.any((f) => !bodyFaces.contains(f))) {
      throw ArgumentError('Face keys must name exact faces in the body');
    }
    _faceKeys = Map.unmodifiable({
      for (final entry in faceKeys.entries)
        copy.copy(entry.value) as Face: entry.key,
    });
    if (key.isEmpty) throw ArgumentError('Output key must not be empty');
    if (kind == OutputKind.face && geometry is! Face ||
        kind == OutputKind.body && geometry is! Solid ||
        kind == OutputKind.planarFace &&
            (geometry is! Face || geometry.surface is! PlaneSurface)) {
      throw ArgumentError('Geometry must match its semantic output kind');
    }
  }

  final String key;
  final OutputKind kind;
  late final CadPrimitive _geometry;
  late final Map<Face, String> _faceKeys;

  // One copy operation preserves correspondence between body and named faces.
  ({CadPrimitive geometry, Map<Face, String> faceKeys}) materialize() {
    final copy = TopologyCopy();
    return (
      geometry: copy.copy(_geometry),
      faceKeys: Map.unmodifiable({
        for (final entry in _faceKeys.entries)
          copy.copy(entry.key) as Face: entry.value,
      }),
    );
  }

  // Each consumer owns its copy, including mutable legacy Vertex vectors.
  CadPrimitive get geometry => TopologyCopy().copy(_geometry);
}
