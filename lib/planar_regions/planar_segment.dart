import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'planar_input.dart';

/// A finite directed segment with parameter zero at start and one at end.
class PlanarSegment extends PlanarInput {
  /// Copies finite endpoints; a zero-length segment is diagnosed by the engine.
  PlanarSegment({
    required String id,
    required Vector2 start,
    required Vector2 end,
  }) : _start = start.clone(),
       _end = end.clone(),
       super(id) {
    if (![start.x, start.y, end.x, end.y].every((v) => v.isFinite)) {
      throw ArgumentError('Segment coordinates must be finite');
    }
  }
  final Vector2 _start;
  final Vector2 _end;

  /// The start point, returned as a defensive copy.
  Vector2 get start => _start.clone();

  /// The end point, returned as a defensive copy.
  Vector2 get end => _end.clone();
}
