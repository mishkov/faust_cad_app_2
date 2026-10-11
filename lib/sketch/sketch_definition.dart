import 'package:equatable/equatable.dart';

import '../document/planar_support.dart';
import '../document/src/immutable_value.dart';
import 'sketch_circle.dart';
import 'sketch_entity_id.dart';
import 'sketch_line_segment.dart';
import 'sketch_point.dart';

/// An immutable unconstrained sketch attached to an infinite planar support.
///
/// Entity IDs are unique across points, segments, and circles. Edits through
/// [copyWith] preserve retained identities and reserve deleted IDs permanently
/// within this definition's lineage. Undo restores the earlier authored value.
final class SketchDefinition extends Equatable {
  SketchDefinition({
    required this.support,
    Iterable<SketchPoint> points = const [],
    Iterable<SketchLineSegment> segments = const [],
    Iterable<SketchCircle> circles = const [],
    Set<SketchEntityId> retiredIds = const {},
  }) : points = _index(points, (p) => p.id),
       segments = _index(segments, (s) => s.id),
       circles = _index(circles, (c) => c.id),
       retiredIds = Set.unmodifiable(retiredIds) {
    final ids = [
      ...this.points.keys,
      ...this.segments.keys,
      ...this.circles.keys,
    ];
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('Sketch entity IDs must be unique across kinds');
    }
    if (ids.any(this.retiredIds.contains)) {
      throw ArgumentError('Deleted sketch entity IDs cannot be reused');
    }
    for (final segment in this.segments.values) {
      _requirePoint(segment.startPointId);
      _requirePoint(segment.endPointId);
    }
    for (final circle in this.circles.values) {
      _requirePoint(circle.centerPointId);
    }
  }

  final PlanarSupport support;
  final Map<SketchEntityId, SketchPoint> points;
  final Map<SketchEntityId, SketchLineSegment> segments;
  final Map<SketchEntityId, SketchCircle> circles;

  /// The deleted identities reserved against reuse, including after encoding.
  final Set<SketchEntityId> retiredIds;

  /// Replaces authored values while retaining IDs and recording deletions.
  ///
  /// A retained ID cannot change entity kind. Removing referenced points requires
  /// removing or updating their consumers in the same edit. New entities require
  /// fresh caller-assigned IDs; no index or coordinate supplies an identity.
  SketchDefinition copyWith({
    PlanarSupport? support,
    Iterable<SketchPoint>? points,
    Iterable<SketchLineSegment>? segments,
    Iterable<SketchCircle>? circles,
  }) {
    final nextPoints = List<SketchPoint>.of(points ?? this.points.values);
    final nextSegments = List<SketchLineSegment>.of(
      segments ?? this.segments.values,
    );
    final nextCircles = List<SketchCircle>.of(circles ?? this.circles.values);
    if (nextPoints.any(
          (p) =>
              this.segments.containsKey(p.id) || this.circles.containsKey(p.id),
        ) ||
        nextSegments.any(
          (s) =>
              this.points.containsKey(s.id) || this.circles.containsKey(s.id),
        ) ||
        nextCircles.any(
          (c) =>
              this.points.containsKey(c.id) || this.segments.containsKey(c.id),
        )) {
      throw ArgumentError('A retained sketch ID cannot change entity kind');
    }
    final nextIds = {
      ...nextPoints.map((p) => p.id),
      ...nextSegments.map((s) => s.id),
      ...nextCircles.map((c) => c.id),
    };
    return SketchDefinition(
      support: support ?? this.support,
      points: nextPoints,
      segments: nextSegments,
      circles: nextCircles,
      retiredIds: {
        ...retiredIds,
        ...this.points.keys.where((id) => !nextIds.contains(id)),
        ...this.segments.keys.where((id) => !nextIds.contains(id)),
        ...this.circles.keys.where((id) => !nextIds.contains(id)),
      },
    );
  }

  /// Encodes geometry and reserved IDs as deeply immutable value parameters.
  ///
  /// The associated support is stored in the owning feature's support field.
  Map<String, Object?> toParameters() => freezeValue({
    'version': 1,
    'points': [
      for (final point in points.values)
        {'id': point.id.value, 'x': point.x, 'y': point.y},
    ],
    'segments': [
      for (final segment in segments.values)
        {
          'id': segment.id.value,
          'start': segment.startPointId.value,
          'end': segment.endPointId.value,
        },
    ],
    'circles': [
      for (final circle in circles.values)
        {
          'id': circle.id.value,
          'center': circle.centerPointId.value,
          'radius': circle.radius,
        },
    ],
    'retiredIds': retiredIds.map((id) => id.value).toList(),
  }) as Map<String, Object?>;

  /// Decodes and validates document-owned values without external registries.
  factory SketchDefinition.fromParameters({
    required PlanarSupport support,
    required Object? parameters,
  }) {
    if (parameters case {
      'version': 1,
      'points': List rawPoints,
      'segments': List rawSegments,
      'circles': List rawCircles,
      'retiredIds': List rawRetired,
    }) {
      return SketchDefinition(
        support: support,
        points: rawPoints.map(
          (p) => switch (p) {
            {'id': String id, 'x': num x, 'y': num y} => SketchPoint(
              id: SketchEntityId(id),
              x: x.toDouble(),
              y: y.toDouble(),
            ),
            _ => throw ArgumentError('Invalid sketch point parameters'),
          },
        ),
        segments: rawSegments.map(
          (s) => switch (s) {
            {'id': String id, 'start': String start, 'end': String end} =>
              SketchLineSegment(
                id: SketchEntityId(id),
                startPointId: SketchEntityId(start),
                endPointId: SketchEntityId(end),
              ),
            _ => throw ArgumentError('Invalid sketch segment parameters'),
          },
        ),
        circles: rawCircles.map(
          (c) => switch (c) {
            {'id': String id, 'center': String center, 'radius': num radius} =>
              SketchCircle(
                id: SketchEntityId(id),
                centerPointId: SketchEntityId(center),
                radius: radius.toDouble(),
              ),
            _ => throw ArgumentError('Invalid sketch circle parameters'),
          },
        ),
        retiredIds: rawRetired
            .map(
              (id) => switch (id) {
                String() => SketchEntityId(id),
                _ => throw ArgumentError('Invalid retired sketch ID'),
              },
            )
            .toSet(),
      );
    }
    throw ArgumentError('Invalid sketch definition parameters');
  }

  void _requirePoint(SketchEntityId id) {
    if (!points.containsKey(id)) {
      throw ArgumentError('Sketch references missing point: $id');
    }
  }

  @override
  List<Object> get props => [support, points, segments, circles, retiredIds];
}

Map<SketchEntityId, T> _index<T>(
  Iterable<T> entities,
  SketchEntityId Function(T) idOf,
) {
  final result = <SketchEntityId, T>{};
  for (final entity in entities) {
    final id = idOf(entity);
    if (result.containsKey(id)) {
      throw ArgumentError('Duplicate sketch entity ID: $id');
    }
    result[id] = entity;
  }
  return Map.unmodifiable(result);
}
