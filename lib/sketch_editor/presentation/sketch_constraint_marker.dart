import 'package:flutter/material.dart';

import '../../sketch/sketch.dart';
import '../sketch_view.dart';

final class SketchConstraintMarker {
  const SketchConstraintMarker(this.constraint, this.position, this.label);
  final SketchConstraint constraint;
  final Offset position;
  final String label;
  Rect get bounds => Rect.fromLTWH(
    position.dx - 2,
    position.dy - 2,
    label.length * 7.5 + 4,
    18,
  );

  static List<SketchConstraintMarker> build(
    SketchDefinition definition,
    SolvedSketch solved,
    SketchView view,
    Size size,
  ) {
    final counts = <String, int>{};
    final result = <SketchConstraintMarker>[];
    for (final c in definition.constraints.values) {
      final positions = <Offset>[];
      for (final id in c.references) {
        final point = solved.points[id];
        final line = solved.segments[id];
        final circle = solved.circles[id];
        if (point != null) positions.add(view.project(point.position, size));
        if (line != null) {
          positions.add(
            view.project(
              (solved.points[line.startPointId]!.position +
                      solved.points[line.endPointId]!.position) /
                  2,
              size,
            ),
          );
        }
        if (circle != null) {
          positions.add(
            view.project(solved.points[circle.centerPointId]!.position, size) +
                Offset(circle.radius * view.scale, 0),
          );
        }
      }
      if (positions.isEmpty) continue;
      final key = c.references.first.value;
      final index = counts.update(key, (v) => v + 1, ifAbsent: () => 0);
      final center =
          positions.reduce((a, b) => a + b) / positions.length.toDouble();
      final symbol = switch (c.kind) {
        SketchConstraintKind.coincident => 'C',
        SketchConstraintKind.horizontal => 'H',
        SketchConstraintKind.vertical => 'V',
        SketchConstraintKind.parallel => '∥',
        SketchConstraintKind.perpendicular => '⊥',
        SketchConstraintKind.equalLengths ||
        SketchConstraintKind.equalRadii => '=',
        SketchConstraintKind.fixedPoint ||
        SketchConstraintKind.fixedPrimitive => 'Fix',
        SketchConstraintKind.pointOnLine ||
        SketchConstraintKind.pointOnCircle => 'On',
        SketchConstraintKind.radius => 'R',
        SketchConstraintKind.diameter => 'Ø',
        _ => 'D',
      };
      result.add(
        SketchConstraintMarker(
          c,
          center + Offset(10, -22 - index * 19.0),
          '$symbol${c.values.length == 1 ? ' ${c.values.single.toStringAsFixed(2)}' : ''}',
        ),
      );
    }
    return result;
  }
}
