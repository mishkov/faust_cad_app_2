import 'sketch_circle.dart';
import 'sketch_entity_id.dart';
import 'sketch_line_segment.dart';
import 'sketch_point.dart';

/// Immutable derived coordinates, separate from authored entities and relations.
final class SolvedSketch {
  SolvedSketch({
    required Map<SketchEntityId, SketchPoint> points,
    required Map<SketchEntityId, SketchLineSegment> segments,
    required Map<SketchEntityId, SketchCircle> circles,
    required Map<SketchEntityId, SketchEntityId> pointRepresentatives,
  }) : points = Map.unmodifiable(points),
       segments = Map.unmodifiable(segments),
       circles = Map.unmodifiable(circles),
       pointRepresentatives = Map.unmodifiable(pointRepresentatives);

  final Map<SketchEntityId, SketchPoint> points;
  final Map<SketchEntityId, SketchLineSegment> segments;
  final Map<SketchEntityId, SketchCircle> circles;

  /// The exact canonical point ID for each shared or explicitly coincident point.
  final Map<SketchEntityId, SketchEntityId> pointRepresentatives;
}
