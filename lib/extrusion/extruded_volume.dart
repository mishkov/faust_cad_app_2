import '../cad_scene/cad_primitivies/solid.dart';
import '../planar_regions/planar_region.dart';
import 'extrusion_face_output.dart';

/// One separate material volume, with its union profile and face lineage.
class ExtrudedVolume {
  /// Freezes outputs while retaining their shared solid topology.
  ExtrudedVolume({
    required this.key,
    required this.solid,
    required this.profile,
    required Iterable<ExtrusionFaceOutput> faces,
  }) : faces = List.unmodifiable(faces);

  /// Deterministic operation-local key.
  final String key;

  /// The closed analytic solid for this material component.
  final Solid solid;

  /// The union component, including its clockwise hole boundaries.
  final PlanarRegion profile;

  /// Faces reference the exact topology used by [solid], without copying it.
  final List<ExtrusionFaceOutput> faces;
}
