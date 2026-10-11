import 'package:equatable/equatable.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'sketch_entity_id.dart';

/// An independently identified point in local sketch coordinates.
final class SketchPoint extends Equatable {
  SketchPoint({required this.id, required this.x, required this.y}) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Sketch point coordinates must be finite');
    }
  }

  final SketchEntityId id;
  final double x;
  final double y;

  /// The local coordinates, returned as a new vector.
  Vector2 get position => Vector2(x, y);

  @override
  List<Object> get props => [id, x, y];
}
