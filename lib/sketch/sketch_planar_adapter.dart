import '../planar_regions/planar_circle.dart';
import '../planar_regions/planar_input.dart';
import '../planar_regions/planar_segment.dart';
import 'sketch_definition.dart';

/// Adapts independent sketch entities to local analytic region-engine inputs.
final class SketchPlanarAdapter {
  const SketchPlanarAdapter();

  /// Publishes segments and circles with their authored entity IDs unchanged.
  ///
  /// Points supply referenced coordinates; isolated points produce no boundary.
  /// Zero-length segments remain inputs for the region engine to diagnose.
  List<PlanarInput> adapt(SketchDefinition definition) => List.unmodifiable([
    for (final segment in definition.segments.values)
      PlanarSegment(
        id: segment.id.value,
        start: definition.points[segment.startPointId]!.position,
        end: definition.points[segment.endPointId]!.position,
      ),
    for (final circle in definition.circles.values)
      PlanarCircle(
        id: circle.id.value,
        center: definition.points[circle.centerPointId]!.position,
        radius: circle.radius,
      ),
  ]);
}
