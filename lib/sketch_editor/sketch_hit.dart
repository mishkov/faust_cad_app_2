import '../sketch/sketch_entity_id.dart';

enum SketchHitKind { point, primitive, region }

final class SketchHit {
  const SketchHit.entity(this.kind, this.entityId) : regionId = null;
  const SketchHit.region(this.regionId)
    : kind = SketchHitKind.region,
      entityId = null;
  final SketchHitKind kind;
  final SketchEntityId? entityId;
  final String? regionId;
}
