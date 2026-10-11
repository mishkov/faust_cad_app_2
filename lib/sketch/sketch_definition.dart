import 'package:equatable/equatable.dart';

import '../document/planar_support.dart';
import '../document/src/immutable_value.dart';
import 'constraints/sketch_constraint.dart';
import 'constraints/sketch_constraint_id.dart';
import 'constraints/sketch_constraint_kind.dart';
import 'sketch_circle.dart';
import 'sketch_entity_id.dart';
import 'sketch_line_segment.dart';
import 'sketch_point.dart';

/// An immutable authored sketch attached to an infinite planar support.
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
    Iterable<SketchConstraint> constraints = const [],
    Set<SketchConstraintId> retiredConstraintIds = const {},
  }) : points = _index(points, (p) => p.id),
       segments = _index(segments, (s) => s.id),
       circles = _index(circles, (c) => c.id),
       retiredIds = Set.unmodifiable(retiredIds),
       constraints = _indexConstraints(constraints),
       retiredConstraintIds = Set.unmodifiable(retiredConstraintIds) {
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
    for (final constraint in this.constraints.values) {
      if (this.retiredConstraintIds.contains(constraint.id)) {
        throw ArgumentError('Deleted constraint IDs cannot be reused');
      }
      _validateConstraint(constraint);
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
  final Map<SketchConstraintId, SketchConstraint> constraints;
  final Set<SketchConstraintId> retiredConstraintIds;

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
    Iterable<SketchConstraint>? constraints,
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
    final nextConstraints = List<SketchConstraint>.of(
      constraints ?? this.constraints.values,
    );
    for (final constraint in nextConstraints) {
      final previous = this.constraints[constraint.id];
      if (previous != null && previous.kind != constraint.kind) {
        throw ArgumentError('A retained constraint ID cannot change kind');
      }
    }
    final nextConstraintIds = nextConstraints.map((c) => c.id).toSet();
    return SketchDefinition(
      constraints: nextConstraints,
      retiredConstraintIds: {
        ...retiredConstraintIds,
        ...this.constraints.keys.where((id) => !nextConstraintIds.contains(id)),
      },
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
    'version': 2,
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
    'constraints': constraints.values.map((c) => c.toParameters()).toList(),
    'retiredConstraintIds': retiredConstraintIds.map((id) => id.value).toList(),
  }) as Map<String, Object?>;

  /// Decodes and validates document-owned values without external registries.
  factory SketchDefinition.fromParameters({
    required PlanarSupport support,
    required Object? parameters,
  }) {
    if (parameters
        case {
          'version': int version,
          'points': List rawPoints,
          'segments': List rawSegments,
          'circles': List rawCircles,
          'retiredIds': List rawRetired,
        }
        when version == 1 || version == 2) {
      final List rawConstraints;
      final List rawRetiredConstraints;
      if (version == 1) {
        rawConstraints = const [];
        rawRetiredConstraints = const [];
      } else if (parameters case {
        'constraints': List constraints,
        'retiredConstraintIds': List retired,
      }) {
        rawConstraints = constraints;
        rawRetiredConstraints = retired;
      } else {
        throw ArgumentError('Missing constraint parameters');
      }
      return SketchDefinition(
        constraints: rawConstraints.map(SketchConstraint.fromParameters),
        retiredConstraintIds: rawRetiredConstraints
            .map(
              (id) => switch (id) {
                String() => SketchConstraintId(id),
                _ => throw ArgumentError('Invalid retired constraint ID'),
              },
            )
            .toSet(),
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

  void _validateConstraint(SketchConstraint c) {
    final kinds = switch (c.kind) {
      SketchConstraintKind.coincident ||
      SketchConstraintKind.distance => ['point', 'point'],
      SketchConstraintKind.pointOnLine => ['point', 'segment'],
      SketchConstraintKind.pointOnCircle => ['point', 'circle'],
      SketchConstraintKind.horizontal ||
      SketchConstraintKind.vertical ||
      SketchConstraintKind.lineLength => ['segment'],
      SketchConstraintKind.parallel ||
      SketchConstraintKind.perpendicular ||
      SketchConstraintKind.equalLengths => ['segment', 'segment'],
      SketchConstraintKind.radius ||
      SketchConstraintKind.diameter => ['circle'],
      SketchConstraintKind.equalRadii => ['circle', 'circle'],
      SketchConstraintKind.fixedPoint => ['point'],
      SketchConstraintKind.fixedPrimitive => ['primitive'],
    };
    for (var i = 0; i < kinds.length; i++) {
      final id = c.references[i];
      final valid = switch (kinds[i]) {
        'point' => points.containsKey(id),
        'segment' => segments.containsKey(id),
        'circle' => circles.containsKey(id),
        _ => segments.containsKey(id) || circles.containsKey(id),
      };
      if (!valid) {
        throw ArgumentError(
          'Constraint ${c.id} has invalid ${kinds[i]} reference: $id',
        );
      }
    }
    if (c.kind == SketchConstraintKind.fixedPrimitive) {
      final circle = circles.containsKey(c.references.single);
      if (c.values.length != (circle ? 3 : 4) || circle && c.values[2] <= 0) {
        throw ArgumentError('Invalid fixed primitive values');
      }
    }
  }

  void _requirePoint(SketchEntityId id) {
    if (!points.containsKey(id)) {
      throw ArgumentError('Sketch references missing point: $id');
    }
  }

  @override
  List<Object> get props => [
    support,
    points,
    segments,
    circles,
    retiredIds,
    constraints,
    retiredConstraintIds,
  ];
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

Map<SketchConstraintId, SketchConstraint> _indexConstraints(
  Iterable<SketchConstraint> constraints,
) {
  final result = <SketchConstraintId, SketchConstraint>{};
  for (final c in constraints) {
    if (result.containsKey(c.id)) {
      throw ArgumentError('Duplicate constraint ID: ${c.id}');
    }
    result[c.id] = c;
  }
  return Map.unmodifiable(result);
}
