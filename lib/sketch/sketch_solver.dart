import 'dart:math' as math;

import 'constraints/sketch_constraint.dart';
import 'constraints/sketch_constraint_id.dart';
import 'constraints/sketch_constraint_kind.dart';
import 'sketch_circle.dart';
import 'sketch_constraint_diagnostic.dart';
import 'sketch_definition.dart';
import 'sketch_drag_target.dart';
import 'sketch_entity_id.dart';
import 'sketch_point.dart';
import 'sketch_solve_result.dart';
import 'sketch_solve_status.dart';
import 'sketch_solver_settings.dart';
import 'solved_sketch.dart';
import 'src/differential.dart';
import 'src/linear_algebra.dart' as algebra;

/// Deterministic bounded nonlinear solving in local sketch coordinates.
final class SketchSolver {
  const SketchSolver();

  /// Solves authored values without modifying geometry or persistent relations.
  ///
  /// Entity and constraint IDs determine all ordering and numerical tie breaks.
  /// Coincidence is eliminated structurally, ensuring exactly shared coordinates.
  /// Rank is computed from the analytic Jacobian at the solution; it describes
  /// local differential freedom, including rigid motion. Iteration exhaustion,
  /// degenerate required directions, and nonfinite arithmetic fail explicitly.
  SketchSolveResult solve(
    SketchDefinition definition, {
    SketchSolverSettings? settings,
    Iterable<SketchDragTarget> dragTargets = const [],
  }) {
    final policy = settings ?? SketchSolverSettings();
    // Invalid interactive references are API errors, rather than model failures.
    final targets = dragTargets.toList()
      ..sort((a, b) => a.pointId.value.compareTo(b.pointId.value));
    final seen = <SketchEntityId>{};
    for (final t in targets) {
      if (!definition.points.containsKey(t.pointId) || !seen.add(t.pointId)) {
        throw ArgumentError('Drag targets require unique existing point IDs');
      }
    }
    SketchSolveResult attempt(
      SketchDefinition sketch,
      List<SketchDragTarget> seeds,
    ) {
      _Solve? pass;
      try {
        pass = _Solve(sketch, policy, seeds);
        return pass.run();
      } on StateError catch (error) {
        return SketchSolveResult(
          status: SketchSolveStatus.numericalFailure,
          iterations: pass?.iteration ?? 0,
          diagnostics: [
            SketchConstraintDiagnostic(
              code: 'numericFailure',
              message: error.message.toString(),
            ),
          ],
        );
      }
    }

    if (targets.isEmpty) return attempt(definition, targets);
    // Reach feasible targets exactly with temporary positional equations first.
    // These never enter the persistent definition or its freedom analysis.
    final temporary = <SketchConstraint>[];
    final usedIds = {
      ...definition.constraints.keys,
      ...definition.retiredConstraintIds,
    };
    for (final target in targets) {
      var name = 'drag:${target.pointId.value}';
      while (usedIds.contains(SketchConstraintId(name))) {
        name = '$name:';
      }
      final id = SketchConstraintId(name);
      usedIds.add(id);
      temporary.add(
        SketchConstraint(
          id: id,
          kind: SketchConstraintKind.fixedPoint,
          references: [target.pointId],
          values: [target.x, target.y],
        ),
      );
    }
    final exact = attempt(
      definition.copyWith(
        constraints: [...definition.constraints.values, ...temporary],
      ),
      targets,
    );
    if (exact.isValid) {
      final seed = definition.copyWith(
        points: exact.geometry!.points.values,
        circles: exact.geometry!.circles.values,
      );
      return attempt(seed, const []);
    }
    // If a target is unreachable, project its seed onto persistent relations.
    final projected = attempt(definition, targets);
    if (projected.isValid) return projected;
    // A drag seed can collapse a required direction. The original feasible
    // model remains usable even when such a target cannot be projected.
    final original = attempt(definition, const []);
    return original.isValid ? original : projected;
  }
}

// These records and implementation share a library to contain numerical state.
typedef _Equation = ({
  Differential value,
  double tolerance,
  SketchConstraintId id,
  bool angular,
});
typedef _Point = (Differential, Differential);

final class _Solve {
  _Solve(this.definition, this.settings, List<SketchDragTarget> targets) {
    pointIds = definition.points.keys.toList()..sort(_compareId);
    circleIds = definition.circles.keys.toList()..sort(_compareId);
    constraints = definition.constraints.values.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    for (final id in pointIds) {
      parents[id] = id;
    }
    for (final c in constraints.where(_joinsPoints)) {
      final a = root(c.references[0]), b = root(c.references[1]);
      if (a == b) {
        redundantCoincidence.add(c.id);
      } else {
        parents[_compareId(a, b) < 0 ? b : a] = _compareId(a, b) < 0 ? a : b;
        coincidenceRank += 2;
      }
    }
    final roots = pointIds.where((id) => root(id) == id).toList();
    originX = pointIds.isEmpty ? 0 : definition.points[pointIds.first]!.x;
    originY = pointIds.isEmpty ? 0 : definition.points[pointIds.first]!.y;
    scale = 0;
    for (final p in definition.points.values) {
      scale = math.max(
        scale,
        math.max((p.x - originX).abs(), (p.y - originY).abs()),
      );
    }
    for (final c in definition.circles.values) {
      scale = math.max(scale, c.radius);
    }
    for (final c in constraints) {
      if ({
        SketchConstraintKind.lineLength,
        SketchConstraintKind.distance,
        SketchConstraintKind.radius,
        SketchConstraintKind.diameter,
      }.contains(c.kind)) {
        scale = math.max(scale, c.values.single);
      }
    }
    if (scale == 0) scale = 1;
    if (!(settings.distanceTolerance / scale).isFinite ||
        settings.distanceTolerance / scale == 0) {
      throw StateError('Model scale cannot represent distanceTolerance');
    }
    if (!scale.isFinite) {
      throw StateError('Coordinate extent exceeds finite arithmetic');
    }
    for (final id in roots) {
      pointOffsets[id] = initial.length;
      final p = definition.points[id]!;
      initial.addAll([(p.x - originX) / scale, (p.y - originY) / scale]);
    }
    for (final id in circleIds) {
      radiusOffsets[id] = initial.length;
      initial.add(definition.circles[id]!.radius / scale);
    }
    if (initial.length > settings.maxVariables) {
      throw StateError('Sketch exceeds maxVariables');
    }
    x = List.of(initial);
    // Multiple targets in one coincidence group use their arithmetic mean.
    final grouped = <SketchEntityId, List<SketchDragTarget>>{};
    for (final t in targets) {
      grouped.putIfAbsent(root(t.pointId), () => []).add(t);
    }
    for (final entry in grouped.entries) {
      final i = pointOffsets[entry.key]!;
      x[i] = entry.value.fold(
        0.0,
        (v, t) => v + (t.x - originX) / scale / entry.value.length,
      );
      x[i + 1] = entry.value.fold(
        0.0,
        (v, t) => v + (t.y - originY) / scale / entry.value.length,
      );
    }
  }
  final SketchDefinition definition;
  final SketchSolverSettings settings;
  late final List<SketchEntityId> pointIds, circleIds;
  late final List<SketchConstraint> constraints;
  final parents = <SketchEntityId, SketchEntityId>{};
  final pointOffsets = <SketchEntityId, int>{},
      radiusOffsets = <SketchEntityId, int>{};
  final redundantCoincidence = <SketchConstraintId>[];
  final initial = <double>[];
  late List<double> x;
  late double originX, originY, scale;
  int coincidenceRank = 0;
  int iteration = 0;
  int singularEscapes = 0;

  SketchEntityId root(SketchEntityId id) {
    final parent = parents[id]!;
    if (parent == id) return id;
    return parents[id] = root(parent);
  }

  List<_Equation> equations(List<double> coordinates) {
    final n = coordinates.length;
    final variables = List.generate(
      n,
      (i) => Differential.variable(coordinates[i], n, i),
    );
    Differential constant(double v) => Differential.constant(v, n);
    _Point point(SketchEntityId id) {
      final i = pointOffsets[root(id)]!;
      return (variables[i], variables[i + 1]);
    }

    _Point difference(_Point a, _Point b) => (a.$1 - b.$1, a.$2 - b.$2);
    _Point line(SketchEntityId id) {
      final segment = definition.segments[id]!;
      return difference(point(segment.endPointId), point(segment.startPointId));
    }

    Differential norm(_Point p) => Differential.norm(p.$1, p.$2);
    Differential radius(SketchEntityId id) => variables[radiusOffsets[id]!];
    final result = <_Equation>[];
    for (final c in constraints) {
      if (_joinsPoints(c)) continue;
      final a = c.references.first;
      final b = c.references.last;
      void add(Differential v, {bool angular = false}) {
        if (result.length >= settings.maxEquations) {
          throw StateError('Sketch exceeds maxEquations');
        }
        result.add((
          value: v,
          id: c.id,
          angular: angular,
          tolerance: angular
              ? settings.angularTolerance
              : settings.distanceTolerance / scale,
        ));
      }

      void fix(SketchEntityId id, double px, double py) {
        final p = point(id);
        add(p.$1 - constant((px - originX) / scale));
        add(p.$2 - constant((py - originY) / scale));
      }

      switch (c.kind) {
        case SketchConstraintKind.coincident:
          continue;
        case SketchConstraintKind.horizontal:
          add(line(a).$2);
        case SketchConstraintKind.vertical:
          add(line(a).$1);
        case SketchConstraintKind.lineLength:
          add(norm(line(a)) - constant(c.values.single / scale));
        case SketchConstraintKind.distance:
          final delta = difference(point(a), point(b));
          if (c.values.single == 0) {
            add(delta.$1);
            add(delta.$2);
          } else {
            add(norm(delta) - constant(c.values.single / scale));
          }
        case SketchConstraintKind.radius:
          add(radius(a) - constant(c.values.single / scale));
        case SketchConstraintKind.diameter:
          // Compare radius to half the diameter so residuals remain lengths.
          add(radius(a) - constant(c.values.single / scale / 2));
        case SketchConstraintKind.equalRadii:
          add(radius(a) - radius(b));
        case SketchConstraintKind.equalLengths:
          add(norm(line(a)) - norm(line(b)));
        case SketchConstraintKind.fixedPoint:
          fix(a, c.values[0], c.values[1]);
        case SketchConstraintKind.fixedPrimitive:
          final segment = definition.segments[a];
          if (segment != null) {
            fix(segment.startPointId, c.values[0], c.values[1]);
            fix(segment.endPointId, c.values[2], c.values[3]);
          } else {
            fix(definition.circles[a]!.centerPointId, c.values[0], c.values[1]);
            add(radius(a) - constant(c.values[2] / scale));
          }
        case SketchConstraintKind.pointOnCircle:
          add(
            norm(
                  difference(
                    point(a),
                    point(definition.circles[b]!.centerPointId),
                  ),
                ) -
                radius(b),
          );
        case SketchConstraintKind.pointOnLine:
          final direction = line(b);
          final length = norm(direction);
          if (length.value == 0) {
            throw StateError('Constraint ${c.id} requires a nonzero line');
          }
          final delta = difference(
            point(a),
            point(definition.segments[b]!.startPointId),
          );
          add((delta.$1 * direction.$2 - delta.$2 * direction.$1) / length);
        case SketchConstraintKind.parallel:
        case SketchConstraintKind.perpendicular:
          final u = line(a), v = line(b);
          final lu = norm(u), lv = norm(v);
          if (lu.value == 0 || lv.value == 0) {
            throw StateError('Constraint ${c.id} requires nonzero lines');
          }
          // Normalize before products to avoid length-squared residuals.
          final ux = u.$1 / lu, uy = u.$2 / lu;
          final vx = v.$1 / lv, vy = v.$2 / lv;
          add(
            c.kind == SketchConstraintKind.parallel
                ? ux * vy - uy * vx
                : ux * vx + uy * vy,
            angular: true,
          );
      }
    }
    if (result.any(
      (e) =>
          !e.value.value.isFinite || !e.value.gradient.every((v) => v.isFinite),
    )) {
      throw StateError('Nonfinite constraint residual or derivative');
    }
    return result;
  }

  bool satisfied(List<_Equation> rows) =>
      rows.every((e) => e.value.value.abs() <= e.tolerance);
  double cost(List<_Equation> rows) =>
      rows.fold(0.0, (v, e) => v + e.value.value * e.value.value);

  SketchSolveResult run() {
    var rows = equations(x);
    final conflictingIds = dimensionConflicts();
    if (conflictingIds.isNotEmpty) {
      return failure(
        rows,
        SketchSolveStatus.conflicting,
        'incompatibleDimensions',
        'Persistent dimensions contradict one another or the triangle inequality.',
        related: conflictingIds,
      );
    }
    var damping = 1e-4;
    for (
      iteration = 0;
      iteration < settings.maxIterations && !satisfied(rows);
      iteration++
    ) {
      final n = x.length;
      final normal = List.generate(n, (_) => List.filled(n, 0.0));
      final gradient = List.filled(n, 0.0);
      for (final e in rows) {
        final g = e.value.gradient;
        for (var i = 0; i < n; i++) {
          gradient[i] += g[i] * e.value.value;
          for (var j = 0; j < n; j++) {
            normal[i][j] += g[i] * g[j];
          }
        }
      }
      final previousCost = cost(rows);
      if (!previousCost.isFinite) throw StateError('Nonfinite solve objective');
      var accepted = false;
      for (var trial = 0; trial < settings.maxDampingTrials; trial++) {
        final matrix = List.generate(
          n,
          (i) => List.generate(n, (j) => normal[i][j] + (i == j ? damping : 0)),
        );
        final step = algebra.solveLinear(
          matrix,
          gradient.map((v) => -v).toList(),
        );
        if (step != null) {
          final candidate = List.generate(n, (i) => x[i] + step[i]);
          if (candidate.every((v) => v.isFinite) &&
              radiusOffsets.values.every((i) => candidate[i] > 0)) {
            List<_Equation>? nextRows;
            try {
              nextRows = equations(candidate);
            } on StateError {
              nextRows = null;
            }
            if (nextRows != null && cost(nextRows) < previousCost) {
              x = candidate;
              rows = nextRows;
              damping = math.max(1e-14, damping / 10);
              accepted = true;
              break;
            }
          }
        }
        damping *= 10;
      }
      if (!accepted) {
        final maxGradient = gradient.fold(0.0, (v, g) => math.max(v, g.abs()));
        // A stationary inconsistent differential system is a local conflict.
        // Nonstationary stalls are numerical failures, never asserted conflicts.
        final jacobian = rows.map((e) => e.value.gradient).toList();
        final rank = algebra.matrixRank(jacobian, settings.rankTolerance);
        final probe = probeRank();
        if (probe.$1 > rank) {
          if (singularEscapes < 3) {
            singularEscapes++;
            x = probe.$2;
            rows = equations(x);
            damping = 1e-4;
            continue;
          }
          return failure(
            rows,
            SketchSolveStatus.numericalFailure,
            'singularStationary',
            'A singular stationary point prevents a reliable conflict classification.',
          );
        }
        final augmentedRank = algebra.matrixRank(
          rows
              .map((e) => [...e.value.gradient, e.value.value / e.tolerance])
              .toList(),
          settings.rankTolerance,
        );
        return failure(
          rows,
          maxGradient <= 1e-9 * math.max(1, math.sqrt(previousCost)) &&
                  augmentedRank > rank
              ? SketchSolveStatus.conflicting
              : SketchSolveStatus.numericalFailure,
          'stalled',
          'The solve stalled with unsatisfied persistent constraints.',
        );
      }
    }
    if (!satisfied(rows)) {
      return failure(
        rows,
        SketchSolveStatus.numericalFailure,
        'iterationLimit',
        'The solve reached maxIterations.',
      );
    }

    final geometry = materialize();
    // Confirm convergence again after converting normalized values to model units.
    final published = List<double>.of(x);
    for (final entry in pointOffsets.entries) {
      final p = geometry.points[entry.key]!;
      published[entry.value] = (p.x - originX) / scale;
      published[entry.value + 1] = (p.y - originY) / scale;
    }
    for (final entry in radiusOffsets.entries) {
      published[entry.value] = geometry.circles[entry.key]!.radius / scale;
    }
    rows = equations(published);
    if (!satisfied(rows)) {
      return failure(
        rows,
        SketchSolveStatus.numericalFailure,
        'numericRange',
        'Model coordinates cannot represent the requested solution tolerance.',
      );
    }
    x = published;
    final accumulated = <List<double>>[];
    final redundant = <SketchConstraintId>[...redundantCoincidence];
    var rank = 0;
    for (final c in constraints.where((c) => !_joinsPoints(c))) {
      final group = rows
          .where((e) => e.id == c.id)
          .map((e) => e.value.gradient)
          .toList();
      accumulated.addAll(group);
      final nextRank = algebra.matrixRank(accumulated, settings.rankTolerance);
      if (nextRank - rank < group.length) redundant.add(c.id);
      rank = nextRank;
    }
    // For metric/linear systems, rank loss away from a regular solution can
    // indicate second-order rigidity rather than an actual free direction.
    // Direction relations can have legitimate dependencies only on their
    // solution manifold, so this conservative singularity check excludes them.
    final metricSystem = constraints.every(
      (c) =>
          c.kind != SketchConstraintKind.parallel &&
          c.kind != SketchConstraintKind.perpendicular &&
          c.kind != SketchConstraintKind.pointOnLine,
    );
    if (metricSystem && probeRank().$1 > rank) {
      return failure(
        rows,
        SketchSolveStatus.numericalFailure,
        'singularSolution',
        'The solution has singular differential freedom; its finite freedom is unresolved.',
      );
    }
    redundant.sort((a, b) => a.value.compareTo(b.value));
    final freedom = x.length - rank;
    return SketchSolveResult(
      status: redundant.isNotEmpty
          ? SketchSolveStatus.redundant
          : freedom == 0
          ? SketchSolveStatus.fullyConstrained
          : SketchSolveStatus.underconstrained,
      iterations: iteration,
      geometry: geometry,
      degreesOfFreedom: freedom,
      rank: rank + coincidenceRank,
      redundantConstraintIds: redundant,
      diagnostics: redundant.map(
        (id) => SketchConstraintDiagnostic(
          constraintId: id,
          code: 'redundant',
          message:
              'Some equations add no independent differential restriction.',
        ),
      ),
    );
  }

  (int, List<double>) probeRank() {
    var best = algebra.matrixRank(
      equations(x).map((e) => e.value.gradient).toList(),
      settings.rankTolerance,
    );
    var coordinates = x;
    for (var probe = 0; probe < 3; probe++) {
      final candidate = List.generate(
        x.length,
        (i) => radiusOffsets.values.contains(i)
            ? x[i] * (1 + 1e-3 * math.sin((i + 1) * (probe + 1)))
            : x[i] + 1e-3 * math.sin((i + 1) * (probe + 1)),
      );
      try {
        final rank = algebra.matrixRank(
          equations(candidate).map((e) => e.value.gradient).toList(),
          settings.rankTolerance,
        );
        if (rank > best) {
          best = rank;
          coordinates = candidate;
        }
      } on StateError {
        // A probe cannot turn an otherwise valid result into nonfinite data.
      }
    }
    return (best, coordinates);
  }

  Set<SketchConstraintId> dimensionConflicts() {
    final distances =
        <
          String,
          (double, SketchEntityId, SketchEntityId, SketchConstraintId)
        >{};
    final radii = <SketchEntityId, (double, SketchConstraintId)>{};
    final conflicts = <SketchConstraintId>{};
    void length(
      SketchEntityId first,
      SketchEntityId second,
      double value,
      SketchConstraintId id,
    ) {
      var a = root(first), b = root(second);
      if (_compareId(a, b) > 0) {
        final t = a;
        a = b;
        b = t;
      }
      // A length-prefixed key avoids collisions with punctuation in caller IDs.
      final key = '${a.value.length}:${a.value}${b.value.length}:${b.value}';
      final previous = distances[key];
      if (a == b && value > settings.distanceTolerance ||
          previous != null &&
              (previous.$1 - value).abs() > 2 * settings.distanceTolerance) {
        conflicts.add(id);
        if (previous != null) conflicts.add(previous.$4);
      }
      distances[key] = (value, a, b, id);
    }

    for (final c in constraints) {
      if (c.kind == SketchConstraintKind.distance) {
        length(c.references[0], c.references[1], c.values.single, c.id);
      } else if (c.kind == SketchConstraintKind.lineLength) {
        final line = definition.segments[c.references.single]!;
        length(line.startPointId, line.endPointId, c.values.single, c.id);
      } else if (c.kind == SketchConstraintKind.radius ||
          c.kind == SketchConstraintKind.diameter) {
        final value =
            c.values.single / (c.kind == SketchConstraintKind.diameter ? 2 : 1);
        final previous = radii[c.references.single];
        if (previous != null &&
            (previous.$1 - value).abs() > 2 * settings.distanceTolerance) {
          conflicts.addAll([previous.$2, c.id]);
        }
        radii[c.references.single] = (value, c.id);
      }
    }
    // Check every fully dimensioned triangle, independently of initial geometry.
    final adjacent =
        <SketchEntityId, Map<SketchEntityId, (double, SketchConstraintId)>>{};
    for (final d in distances.values) {
      adjacent.putIfAbsent(d.$2, () => {})[d.$3] = (d.$1, d.$4);
      adjacent.putIfAbsent(d.$3, () => {})[d.$2] = (d.$1, d.$4);
    }
    for (final d in distances.values) {
      for (final edge in adjacent[d.$2]!.entries) {
        final other = adjacent[d.$3]![edge.key];
        if (other != null &&
            d.$1 - edge.value.$1 - other.$1 > 3 * settings.distanceTolerance) {
          conflicts.addAll([d.$4, edge.value.$2, other.$2]);
        }
      }
    }
    return conflicts;
  }

  SketchSolveResult failure(
    List<_Equation> rows,
    SketchSolveStatus status,
    String code,
    String message, {
    Set<SketchConstraintId> related = const {},
  }) {
    final diagnostics = <SketchConstraintDiagnostic>[
      SketchConstraintDiagnostic(code: code, message: message),
    ];
    for (final c in constraints) {
      final unsatisfied = rows
          .where(
            (e) =>
                e.id == c.id &&
                (related.contains(c.id) || e.value.value.abs() > e.tolerance),
          )
          .toList();
      if (unsatisfied.isEmpty) continue;
      final worst = unsatisfied.reduce(
        (a, b) =>
            a.value.value.abs() / a.tolerance >=
                b.value.value.abs() / b.tolerance
            ? a
            : b,
      );
      final modelResidual =
          worst.value.value.abs() * (worst.angular ? 1 : scale);
      diagnostics.add(
        SketchConstraintDiagnostic(
          constraintId: c.id,
          code: related.contains(c.id) ? 'conflictingDimension' : 'unsatisfied',
          message: related.contains(c.id)
              ? 'Constraint ${c.id} participates in incompatible persistent dimensions.'
              : 'Constraint ${c.id} exceeds its ${worst.angular ? 'angular' : 'distance'} tolerance.',
          residual: modelResidual.isFinite ? modelResidual : null,
          tolerance: worst.angular
              ? settings.angularTolerance
              : settings.distanceTolerance,
        ),
      );
    }
    return SketchSolveResult(
      status: status,
      iterations: iteration,
      diagnostics: diagnostics,
    );
  }

  SolvedSketch materialize() => SolvedSketch(
    points: {for (final id in pointIds) id: makePoint(id)},
    segments: definition.segments,
    circles: {for (final id in circleIds) id: makeCircle(id)},
    pointRepresentatives: {for (final id in pointIds) id: root(id)},
  );

  SketchCircle makeCircle(SketchEntityId id) {
    final i = radiusOffsets[id]!;
    final radius = x[i] == initial[i]
        ? definition.circles[id]!.radius
        : x[i] * scale;
    if (!radius.isFinite || radius <= 0) {
      throw StateError('Solved radius cannot be represented');
    }
    return SketchCircle(
      id: id,
      centerPointId: definition.circles[id]!.centerPointId,
      radius: radius,
    );
  }

  SketchPoint makePoint(SketchEntityId id) {
    final canonical = root(id);
    final original = definition.points[canonical]!;
    final i = pointOffsets[canonical]!;
    final px = x[i] == initial[i] ? original.x : originX + x[i] * scale;
    final py = x[i + 1] == initial[i + 1]
        ? original.y
        : originY + x[i + 1] * scale;
    if (!px.isFinite || !py.isFinite) {
      throw StateError('Solved coordinates exceed finite arithmetic');
    }
    return SketchPoint(id: id, x: px, y: py);
  }
}

int _compareId(SketchEntityId a, SketchEntityId b) =>
    a.value.compareTo(b.value);

bool _joinsPoints(SketchConstraint c) =>
    c.kind == SketchConstraintKind.coincident ||
    c.kind == SketchConstraintKind.distance && c.values.single == 0;
