import 'sketch_entity_id.dart';

/// A temporary desired point position used to seed a constrained drag solve.
///
/// Targets do not become persistent constraints or affect reported freedom.
/// Reachable targets are solved as temporary positions. Persistent constraints
/// take precedence; unreachable targets are projected by solving from their
/// seed positions, and need not be reached exactly.
final class SketchDragTarget {
  SketchDragTarget({required this.pointId, required this.x, required this.y}) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Drag target must be finite');
    }
  }
  final SketchEntityId pointId;
  final double x;
  final double y;
}
