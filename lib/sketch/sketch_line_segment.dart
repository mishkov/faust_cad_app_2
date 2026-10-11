import 'package:equatable/equatable.dart';

import 'sketch_entity_id.dart';

/// A directed line segment referencing two independent sketch points.
final class SketchLineSegment extends Equatable {
  const SketchLineSegment({
    required this.id,
    required this.startPointId,
    required this.endPointId,
  });

  final SketchEntityId id;
  final SketchEntityId startPointId;
  final SketchEntityId endPointId;

  @override
  List<Object> get props => [id, startPointId, endPointId];
}
