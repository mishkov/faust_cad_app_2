import 'package:equatable/equatable.dart';

import '../sketch_definition.dart';
import '../sketch_entity_id.dart';
import 'sketch_constraint_id.dart';
import 'sketch_constraint_kind.dart';

/// An immutable relation with explicit ordered entity references and values.
///
/// Reference roles are documented on [SketchConstraintKind]. Dimensions use
/// model units. Fixed coordinates are local to the sketch support. Point-on-line
/// uses the supporting infinite line, including points beyond either endpoint.
final class SketchConstraint extends Equatable {
  SketchConstraint({
    required this.id,
    required this.kind,
    required Iterable<SketchEntityId> references,
    Iterable<double> values = const [],
  }) : references = List.unmodifiable(references),
       values = List.unmodifiable(values) {
    final referenceCount = switch (kind) {
      SketchConstraintKind.coincident ||
      SketchConstraintKind.pointOnLine ||
      SketchConstraintKind.pointOnCircle ||
      SketchConstraintKind.parallel ||
      SketchConstraintKind.perpendicular ||
      SketchConstraintKind.distance ||
      SketchConstraintKind.equalLengths ||
      SketchConstraintKind.equalRadii => 2,
      _ => 1,
    };
    final valueCount = switch (kind) {
      SketchConstraintKind.lineLength ||
      SketchConstraintKind.distance ||
      SketchConstraintKind.radius ||
      SketchConstraintKind.diameter => 1,
      SketchConstraintKind.fixedPoint => 2,
      SketchConstraintKind.fixedPrimitive => this.values.length,
      _ => 0,
    };
    if (this.references.length != referenceCount ||
        this.values.length != valueCount ||
        !this.values.every((v) => v.isFinite) ||
        kind == SketchConstraintKind.fixedPrimitive &&
            this.values.length != 3 &&
            this.values.length != 4) {
      throw ArgumentError(
        'Invalid ${kind.name} constraint references or values',
      );
    }
    if ((kind == SketchConstraintKind.lineLength ||
                kind == SketchConstraintKind.radius ||
                kind == SketchConstraintKind.diameter) &&
            this.values.single <= 0 ||
        kind == SketchConstraintKind.distance && this.values.single < 0) {
      throw ArgumentError('Constraint dimension is outside its valid range');
    }
  }

  /// Captures authored coordinates and radius as explicit persistent fixed data.
  factory SketchConstraint.fixPrimitive({
    required SketchConstraintId id,
    required SketchDefinition sketch,
    required SketchEntityId primitiveId,
  }) {
    final segment = sketch.segments[primitiveId];
    final circle = sketch.circles[primitiveId];
    final values = <double>[];
    if (segment != null) {
      for (final pointId in [segment.startPointId, segment.endPointId]) {
        final point = sketch.points[pointId]!;
        values.addAll([point.x, point.y]);
      }
    } else if (circle != null) {
      final center = sketch.points[circle.centerPointId]!;
      values.addAll([center.x, center.y, circle.radius]);
    } else {
      throw ArgumentError('Fixed primitive must reference a segment or circle');
    }
    return SketchConstraint(
      id: id,
      kind: SketchConstraintKind.fixedPrimitive,
      references: [primitiveId],
      values: values,
    );
  }

  final SketchConstraintId id;
  final SketchConstraintKind kind;
  final List<SketchEntityId> references;
  final List<double> values;

  Map<String, Object?> toParameters() => {
    'id': id.value,
    'kind': kind.name,
    'references': references.map((r) => r.value).toList(),
    'values': values,
  };

  factory SketchConstraint.fromParameters(Object? parameters) {
    if (parameters case {
      'id': String id,
      'kind': String kind,
      'references': List references,
      'values': List values,
    }) {
      return SketchConstraint(
        id: SketchConstraintId(id),
        kind: SketchConstraintKind.values.firstWhere(
          (k) => k.name == kind,
          orElse: () => throw ArgumentError('Unknown constraint kind: $kind'),
        ),
        references: references.map(
          (r) => switch (r) {
            String() => SketchEntityId(r),
            _ => throw ArgumentError('Invalid constraint reference'),
          },
        ),
        values: values.map(
          (v) => switch (v) {
            num() => v.toDouble(),
            _ => throw ArgumentError('Invalid constraint value'),
          },
        ),
      );
    }
    throw ArgumentError('Invalid constraint parameters');
  }

  @override
  List<Object> get props => [id, kind, references, values];
}
