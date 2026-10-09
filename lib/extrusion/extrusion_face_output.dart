import '../cad_scene/cad_primitivies/face.dart';
import '../planar_regions/boundary_portion.dart';
import '../planar_regions/region_reference.dart';

/// A generated face's role relative to the authored profile plane.
enum ExtrusionFaceRole { startCap, endCap, wall }

/// Analytic face geometry and lineage for a future feature-output adapter.
class ExtrusionFaceOutput {
  /// Freezes face lineage while retaining the generated topology.
  ExtrusionFaceOutput({
    required this.key,
    required this.face,
    required this.role,
    required Iterable<RegionReference> regions,
    required Iterable<BoundaryPortion> boundaries,
  }) : regions = List.unmodifiable(regions),
       boundaries = List.unmodifiable(boundaries);

  /// Deterministic operation-local key, never a persistent topological name.
  final String key;

  /// The exact face instance in the generated solid.
  final Face face;

  /// The generation role, independent of material orientation.
  final ExtrusionFaceRole role;

  /// Original selected cells contributing to this material component.
  final List<RegionReference> regions;

  /// Union boundaries in profile traversal order, retaining all source intervals.
  ///
  /// Walls have one portion; caps have the outer loop followed by hole loops.
  /// These intervals describe profile traversal even when the face wire reverses.
  final List<BoundaryPortion> boundaries;
}
