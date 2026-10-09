import '../cad_scene/geometry/geometry_tolerance.dart';
import 'planar_input.dart';
import 'region_result.dart';
import 'src/arrangement.dart';

/// Builds bounded analytic cells without sketch, Wire, Face, UI, or solid inputs.
class PlanarRegionEngine {
  /// Creates an engine with the shared model-space diagnostic policy.
  const PlanarRegionEngine({this.tolerance = GeometryTolerance.defaults});

  /// The distance threshold for tiny-input warnings, never for endpoint snapping.
  final GeometryTolerance tolerance;

  /// Intersects, splits, and walks independently identified lines and circles.
  ///
  /// Duplicate IDs and unsupported input types throw [ArgumentError]. Unresolved
  /// numerical topology returns an invalid result with no selectable regions.
  RegionResult build(Iterable<PlanarInput> inputs) =>
      Arrangement(inputs, tolerance).build();
}
