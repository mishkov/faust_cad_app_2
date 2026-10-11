import 'package:equatable/equatable.dart';

import 'sketch_entity_id.dart';

/// An analytic circle referencing an independent center point.
final class SketchCircle extends Equatable {
  SketchCircle({
    required this.id,
    required this.centerPointId,
    required this.radius,
  }) {
    if (!radius.isFinite || radius <= 0) {
      throw ArgumentError('Sketch circle radius must be finite and positive');
    }
  }

  final SketchEntityId id;
  final SketchEntityId centerPointId;
  final double radius;

  @override
  List<Object> get props => [id, centerPointId, radius];
}
