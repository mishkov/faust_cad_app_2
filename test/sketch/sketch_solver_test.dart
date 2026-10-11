import 'dart:math' as math;

import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/constraint_fixtures.dart';

void main() {
  test(
    'known anchored horizontal and vertical line solutions keep authored data',
    () {
      for (final vertical in [false, true]) {
        final definition = sketch(
          points: [p('a', 1, 1), p('b', 4, 2)],
          lines: [l('ab', 'a', 'b')],
          constraints: [
            c('anchor', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
            c(
              'direction',
              vertical
                  ? SketchConstraintKind.vertical
                  : SketchConstraintKind.horizontal,
              ['ab'],
            ),
            c('length', SketchConstraintKind.lineLength, ['ab'], [5]),
          ],
        );
        final result = solver.solve(definition);
        expect(result.status, SketchSolveStatus.fullyConstrained);
        expect(result.degreesOfFreedom, 0);
        at(result.geometry!, 'a', 0, 0);
        at(result.geometry!, 'b', vertical ? 0 : 5, vertical ? 5 : 0);
        expect(definition.points[eid('b')], p('b', 4, 2));
      }
    },
  );

  test('independent 3-4-5 triangle solution and free rigid motion', () {
    final relations = [
      c('ab', SketchConstraintKind.distance, ['a', 'b'], [4]),
      c('ac', SketchConstraintKind.distance, ['a', 'c'], [3]),
      c('bc', SketchConstraintKind.distance, ['b', 'c'], [5]),
    ];
    final free = sketch(
      points: [p('a', 2, 1), p('b', 5, 2), p('c', 1, 4)],
      constraints: relations,
    );
    final result = solver.solve(free);
    expect(result.status, SketchSolveStatus.underconstrained);
    expect(result.degreesOfFreedom, 3); // two translations and one rotation.
    expect(result.rank, 3);
    for (final pair in [('a', 'b', 4.0), ('a', 'c', 3.0), ('b', 'c', 5.0)]) {
      expect(
        distance(result.geometry!, pair.$1, pair.$2),
        closeTo(pair.$3, 1e-8),
      );
    }
    final anchored = free.copyWith(
      segments: [l('line', 'a', 'b')],
      constraints: [
        ...relations,
        c('fixed', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
        c('horizontal', SketchConstraintKind.horizontal, ['line']),
      ],
    );
    final known = solver.solve(anchored);
    expect(known.status, SketchSolveStatus.fullyConstrained);
    at(known.geometry!, 'b', 4, 0);
    at(known.geometry!, 'c', 0, 3);
  });

  test('parallel perpendicular and equal lengths solve a rigid rectangle', () {
    final definition = sketch(
      points: [
        p('a', 0, 0),
        p('b', 4.2, 0.1),
        p('c', 4.1, 3.2),
        p('d', -0.1, 3),
      ],
      lines: [
        l('ab', 'a', 'b'),
        l('bc', 'b', 'c'),
        l('cd', 'c', 'd'),
        l('da', 'd', 'a'),
      ],
      constraints: [
        c('abLength', SketchConstraintKind.lineLength, ['ab'], [4]),
        c('bcLength', SketchConstraintKind.lineLength, ['bc'], [3]),
        c('rightAngle', SketchConstraintKind.perpendicular, ['ab', 'bc']),
        c('parallel1', SketchConstraintKind.parallel, ['ab', 'cd']),
        c('parallel2', SketchConstraintKind.parallel, ['bc', 'da']),
        c('equal', SketchConstraintKind.equalLengths, ['ab', 'cd']),
      ],
    );
    final result = solver.solve(definition);
    expect(result.isValid, isTrue, reason: result.toDiagnostics().toString());
    expect(result.degreesOfFreedom, 3);
    final s = result.geometry!;
    expect(distance(s, 'a', 'c'), closeTo(5, 1e-7));
    expect(distance(s, 'a', 'd'), closeTo(3, 1e-7));
    final anchored = solver.solve(
      definition.copyWith(
        constraints: [
          ...definition.constraints.values,
          c('anchor', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
          c('orientation', SketchConstraintKind.horizontal, ['ab']),
        ],
      ),
    );
    expect(anchored.degreesOfFreedom, 0);
    at(anchored.geometry!, 'a', 0, 0);
    at(anchored.geometry!, 'b', 4, 0);
    at(anchored.geometry!, 'c', 4, 3);
    at(anchored.geometry!, 'd', 0, 3);
  });

  test(
    'point-on-line uses the infinite supporting line beyond its endpoints',
    () {
      final base = sketch(
        points: [p('a', 1, 2), p('b', 4, 2), p('q', 10, 7)],
        lines: [l('line', 'a', 'b')],
      );
      final definition = base.copyWith(
        constraints: [
          SketchConstraint.fixPrimitive(
            id: SketchConstraintId('fixedLine'),
            sketch: base,
            primitiveId: eid('line'),
          ),
          c('on', SketchConstraintKind.pointOnLine, ['q', 'line']),
        ],
      );
      final result = solver.solve(definition);
      expect(result.isValid, isTrue);
      expect(result.degreesOfFreedom, 1);
      expect(result.geometry!.points[eid('q')]!.x, greaterThan(4));
      expect(result.geometry!.points[eid('q')]!.y, closeTo(2, 1e-8));
      at(result.geometry!, 'a', 1, 2);
    },
  );

  test('fixed circle and point-on-circle have a known radial solution', () {
    final base = sketch(
      points: [p('o', 1, 2), p('q', 10, 2)],
      circles: [circle('circle', 'o', 5)],
    );
    final result = solver.solve(
      base.copyWith(
        constraints: [
          SketchConstraint.fixPrimitive(
            id: SketchConstraintId('fixedCircle'),
            sketch: base,
            primitiveId: eid('circle'),
          ),
          c('on', SketchConstraintKind.pointOnCircle, ['q', 'circle']),
        ],
      ),
    );
    expect(result.degreesOfFreedom, 1);
    at(result.geometry!, 'q', 6, 2);
    at(result.geometry!, 'o', 1, 2);
    expect(result.geometry!.circles[eid('circle')]!.radius, closeTo(5, 1e-8));
  });

  test(
    'radius diameter and equal radii are dimensional and allow center freedom',
    () {
      final definition = sketch(
        points: [p('a', 0, 0), p('b', 10, 5)],
        circles: [circle('c1', 'a', 1), circle('c2', 'b', 7)],
        constraints: [
          c('diameter', SketchConstraintKind.diameter, ['c1'], [6]),
          c('equal', SketchConstraintKind.equalRadii, ['c1', 'c2']),
        ],
      );
      final result = solver.solve(definition);
      expect(result.status, SketchSolveStatus.underconstrained);
      expect(result.degreesOfFreedom, 4);
      expect(
        result.geometry!.circles.values.map((c) => c.radius),
        everyElement(closeTo(3, 2e-8)),
      );
      final redundant = solver.solve(
        definition.copyWith(
          constraints: [
            ...definition.constraints.values,
            c('radius', SketchConstraintKind.radius, ['c1'], [3]),
          ],
        ),
      );
      expect(redundant.status, SketchSolveStatus.redundant);
      expect(redundant.degreesOfFreedom, 4);
    },
  );

  test('duplicate equations are redundant without removing real freedom', () {
    final definition = sketch(
      points: [p('a', 0, 0), p('b', 4, 1)],
      lines: [l('line', 'a', 'b')],
      constraints: [
        c('a', SketchConstraintKind.horizontal, ['line']),
        c('b', SketchConstraintKind.horizontal, ['line']),
        c('c', SketchConstraintKind.lineLength, ['line'], [4]),
      ],
    );
    final result = solver.solve(definition);
    expect(result.status, SketchSolveStatus.redundant);
    expect(result.degreesOfFreedom, 2);
    expect(result.redundantConstraintIds, [SketchConstraintId('b')]);
    final fully = solver.solve(
      definition.copyWith(
        constraints: [
          ...definition.constraints.values,
          c('anchor', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
        ],
      ),
    );
    expect(fully.status, SketchSolveStatus.redundant);
    expect(fully.degreesOfFreedom, 0);
  });

  test('incompatible circle dimensions conflict and removing one recovers', () {
    final definition = sketch(
      points: [p('o', 0, 0)],
      circles: [circle('circle', 'o', 1)],
      constraints: [
        c('r1', SketchConstraintKind.radius, ['circle'], [3]),
        c('r2', SketchConstraintKind.radius, ['circle'], [4]),
      ],
    );
    final failed = solver.solve(definition);
    expect(failed.status, SketchSolveStatus.conflicting);
    expect(failed.geometry, isNull);
    expect(failed.degreesOfFreedom, isNull);
    expect(
      failed.diagnostics
          .where((d) => d.constraintId != null)
          .map((d) => d.constraintId!.value),
      ['r1', 'r2'],
    );
    final recovered = solver.solve(
      definition.copyWith(constraints: [definition.constraints.values.first]),
    );
    expect(recovered.isValid, isTrue);
    expect(recovered.geometry!.circles.values.single.radius, closeTo(3, 1e-8));
  });

  test(
    'conflicting fixed positions and line dimensions are not numerical limits',
    () {
      final definition = sketch(
        points: [p('a', 0, 0), p('b', 3, 0)],
        lines: [l('line', 'a', 'b')],
        constraints: [
          c('fixA', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
          c('fixB', SketchConstraintKind.fixedPoint, ['b'], [3, 0]),
          c('length', SketchConstraintKind.lineLength, ['line'], [5]),
        ],
      );
      expect(solver.solve(definition).status, SketchSolveStatus.conflicting);
      final doubleFixed = sketch(
        points: [p('a', 0, 0)],
        constraints: [
          c('fixed1', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
          c('fixed2', SketchConstraintKind.fixedPoint, ['a'], [2, 0]),
        ],
      );
      expect(solver.solve(doubleFixed).status, SketchSolveStatus.conflicting);
    },
  );

  test(
    'limits and undefined directions explicitly produce numerical failure',
    () {
      final definition = sketch(
        points: [p('a', 0, 0), p('b', 1, 2)],
        lines: [l('line', 'a', 'b')],
        constraints: [
          c('h', SketchConstraintKind.horizontal, ['line']),
        ],
      );
      final limited = solver.solve(
        definition,
        settings: SketchSolverSettings(maxIterations: 0),
      );
      expect(limited.status, SketchSolveStatus.numericalFailure);
      expect(limited.diagnostics.first.code, 'iterationLimit');
      expect(limited.geometry, isNull);
      final collapsed = sketch(
        points: [p('a', 0, 0), p('b', 0, 0), p('q', 1, 1)],
        lines: [l('line', 'a', 'b')],
        constraints: [
          c('on', SketchConstraintKind.pointOnLine, ['q', 'line']),
        ],
      );
      expect(
        solver.solve(collapsed).status,
        SketchSolveStatus.numericalFailure,
      );
      expect(
        solver
            .solve(definition, settings: SketchSolverSettings(maxVariables: 2))
            .status,
        SketchSolveStatus.numericalFailure,
      );
    },
  );

  test(
    'shared circle-line geometry and explicit coincidences solve together',
    () {
      final definition = sketch(
        points: [p('o', 0.2, 0.1), p('b', 2, 1), p('alias', 2.1, 1.2)],
        lines: [l('line', 'o', 'alias')],
        circles: [circle('circle', 'o', 1)],
        constraints: [
          c('fixed', SketchConstraintKind.fixedPoint, ['o'], [0, 0]),
          c('coincident', SketchConstraintKind.coincident, ['b', 'alias']),
          c('horizontal', SketchConstraintKind.horizontal, ['line']),
          c('radius', SketchConstraintKind.radius, ['circle'], [3]),
          c('onCircle', SketchConstraintKind.pointOnCircle, ['b', 'circle']),
        ],
      );
      final result = solver.solve(definition);
      expect(result.status, SketchSolveStatus.fullyConstrained);
      expect(result.degreesOfFreedom, 0);
      at(result.geometry!, 'b', 3, 0);
      expect(
        result.geometry!.points[eid('b')]!.position,
        result.geometry!.points[eid('alias')]!.position,
      );
    },
  );

  test(
    'nonfinite range and equation budget fail with inspectable diagnostics',
    () {
      final extreme = sketch(
        points: [p('a', -1e308, 0), p('b', 1e308, 0)],
        constraints: [
          c('d', SketchConstraintKind.distance, ['a', 'b'], [1]),
        ],
      );
      expect(solver.solve(extreme).status, SketchSolveStatus.numericalFailure);
      final budget = sketch(
        points: [p('a', 0, 0)],
        constraints: [
          c('fixed', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
        ],
      );
      final failed = solver.solve(
        budget,
        settings: SketchSolverSettings(maxEquations: 1),
      );
      expect(failed.status, SketchSolveStatus.numericalFailure);
      expect(failed.diagnostics.first.message, contains('maxEquations'));
    },
  );

  test('positive distance can grow from coincident initial coordinates', () {
    final result = solver.solve(
      sketch(
        points: [p('a', 0, 0), p('b', 0, 0)],
        constraints: [
          c('distance', SketchConstraintKind.distance, ['a', 'b'], [5]),
        ],
      ),
    );
    expect(result.isValid, isTrue);
    expect(distance(result.geometry!, 'a', 'b'), closeTo(5, 1e-8));
    expect(result.degreesOfFreedom, 3);
  });

  test('zero distance restricts both coordinates rather than counting one equation', () {
    final result = solver.solve(
      sketch(
        points: [p('a', 0, 0), p('b', 2, 3)],
        constraints: [
          c('zero', SketchConstraintKind.distance, ['a', 'b'], [0]),
        ],
      ),
    );
    expect(result.isValid, isTrue);
    expect(result.degreesOfFreedom, 2);
  });

  test(
    'coincidence chains share exact planar endpoints and cycles are redundant',
    () {
      final definition = sketch(
        points: [
          p('a', 0, 0),
          p('b', 4, 0),
          p('c', 4, 3),
          p('d', 0, 3),
          p('end', 0, 0.1),
          p('alias', 0, 0.2),
        ],
        lines: [
          l('ab', 'a', 'b'),
          l('bc', 'b', 'c'),
          l('cd', 'c', 'd'),
          l('da', 'd', 'end'),
        ],
        constraints: [
          c('one', SketchConstraintKind.coincident, ['a', 'end']),
          c('two', SketchConstraintKind.coincident, ['end', 'alias']),
          c('three', SketchConstraintKind.coincident, ['alias', 'a']),
        ],
      );
      final solved = solver.solve(definition);
      expect(solved.status, SketchSolveStatus.redundant);
      expect(solved.degreesOfFreedom, 8);
      expect(
        solved.geometry!.points[eid('a')]!.position,
        solved.geometry!.points[eid('end')]!.position,
      );
      expect(solved.geometry!.pointRepresentatives[eid('alias')], eid('a'));
      final regions = const PlanarRegionEngine().build(
        const SketchPlanarAdapter().adaptSolved(solved.geometry!),
      );
      expect(regions.regions, hasLength(1));
      expect(regions.regions.single.area, 12);
    },
  );

  test('arbitrarily small gaps without explicit coincidence remain open', () {
    for (final gap in [1e-5, 1e-9, 1e-12]) {
      final definition = sketch(
        points: [
          p('a', 0, 0),
          p('b', 4, 0),
          p('c', 4, 3),
          p('d', 0, 3),
          p('end', 0, gap),
        ],
        lines: [
          l('ab', 'a', 'b'),
          l('bc', 'b', 'c'),
          l('cd', 'c', 'd'),
          l('da', 'd', 'end'),
        ],
      );
      final solved = solver.solve(definition).geometry!;
      expect(solved.points[eid('end')]!.y, gap);
      final regions = const PlanarRegionEngine().build(
        const SketchPlanarAdapter().adaptSolved(solved),
      );
      expect(regions.regions, isEmpty);
      expect(regions.diagnostics.map((d) => d.code), contains('openBoundary'));
    }
  });

  test(
    'reachable drag targets move free geometry and do not remove freedom',
    () {
      final definition = sketch(
        points: [p('a', 0, 0), p('b', 5, 0)],
        lines: [l('line', 'a', 'b')],
        constraints: [
          c('h', SketchConstraintKind.horizontal, ['line']),
          c('len', SketchConstraintKind.lineLength, ['line'], [5]),
        ],
      );
      final result = solver.solve(
        definition,
        dragTargets: [SketchDragTarget(pointId: eid('b'), x: 10, y: 4)],
      );
      expect(result.isValid, isTrue);
      at(result.geometry!, 'b', 10, 4);
      at(result.geometry!, 'a', 5, 4);
      expect(result.degreesOfFreedom, 2);
      expect(result.status, SketchSolveStatus.underconstrained);
      expect(definition.points[eid('b')], p('b', 5, 0));
      final fixed = definition.copyWith(
        constraints: [
          ...definition.constraints.values,
          c('anchor', SketchConstraintKind.fixedPoint, ['a'], [0, 0]),
        ],
      );
      final unreachable = solver.solve(
        fixed,
        dragTargets: [SketchDragTarget(pointId: eid('b'), x: 10, y: 4)],
      );
      expect(unreachable.isValid, isTrue);
      expect(unreachable.degreesOfFreedom, 0);
      at(unreachable.geometry!, 'b', 5, 0);
    },
  );

  test(
    'distance and angular tolerances retain their units across model scales',
    () {
      for (final size in [0.001, 10000.0]) {
        final base = sketch(
          points: [p('a', 0, 0), p('b', size, 0), p('c', size * 0.2, size)],
          lines: [l('base', 'a', 'b'), l('side', 'a', 'c')],
        );
        final result = solver.solve(
          base.copyWith(
            constraints: [
              SketchConstraint.fixPrimitive(
                id: SketchConstraintId('fixed'),
                sketch: base,
                primitiveId: eid('base'),
              ),
              c('angle', SketchConstraintKind.perpendicular, ['base', 'side']),
              c('length', SketchConstraintKind.lineLength, ['side'], [size]),
            ],
          ),
          settings: SketchSolverSettings(
            distanceTolerance: 1e-8,
            angularTolerance: 1e-11,
          ),
        );
        expect(
          result.isValid,
          isTrue,
          reason: result.toDiagnostics().toString(),
        );
        final s = result.geometry!;
        expect((distance(s, 'a', 'c') - size).abs(), lessThanOrEqualTo(1e-8));
        final u = s.points[eid('b')]!.position - s.points[eid('a')]!.position;
        final v = s.points[eid('c')]!.position - s.points[eid('a')]!.position;
        expect(
          (u.dot(v) / (u.length * v.length)).abs(),
          lessThanOrEqualTo(1e-11),
        );
      }
    },
  );

  test(
    'repeat solves and collection permutations are bitwise deterministic',
    () {
      final definition = sketch(
        points: [p('a', 1, 2), p('b', 4, 3), p('c', 3, 8)],
        circles: [circle('circle', 'c', 1)],
        lines: [l('line', 'a', 'b')],
        constraints: [
          c('h', SketchConstraintKind.horizontal, ['line']),
          c('len', SketchConstraintKind.lineLength, ['line'], [5]),
          c('radius', SketchConstraintKind.radius, ['circle'], [3]),
          c('on', SketchConstraintKind.pointOnCircle, ['b', 'circle']),
        ],
      );
      final first = solver.solve(definition);
      expect(first.isValid, isTrue);
      for (var i = 0; i < 10; i++) {
        final permuted = sketch(
          points: definition.points.values.toList().reversed.toList(),
          lines: definition.segments.values.toList(),
          circles: definition.circles.values.toList(),
          constraints: definition.constraints.values.toList().reversed.toList(),
        );
        final again = solver.solve(permuted);
        expect(again.toDiagnostics(), first.toDiagnostics());
        expect(again.geometry!.points, first.geometry!.points);
        expect(again.geometry!.circles, first.geometry!.circles);
      }
    },
  );

  test('singular collinear seeds recover an independently known triangle', () {
    final result = solver.solve(
      sketch(
        points: [p('a', 0, 0), p('b', 4, 0), p('c', 1, 0)],
        constraints: [
          c('ab', SketchConstraintKind.distance, ['a', 'b'], [4]),
          c('ac', SketchConstraintKind.distance, ['a', 'c'], [3]),
          c('bc', SketchConstraintKind.distance, ['b', 'c'], [5]),
        ],
      ),
    );
    expect(result.isValid, isTrue, reason: result.toDiagnostics().toString());
    expect(result.degreesOfFreedom, 3);
    expect(distance(result.geometry!, 'a', 'b'), closeTo(4, 1e-8));
    expect(distance(result.geometry!, 'a', 'c'), closeTo(3, 1e-8));
    expect(distance(result.geometry!, 'b', 'c'), closeTo(5, 1e-8));
  });

  test('singular satisfied lengths do not report spurious finite freedom', () {
    final result = solver.solve(
      sketch(
        points: [p('a', 0, 0), p('b', 1, 0), p('c', 2, 0)],
        constraints: [
          c('ab', SketchConstraintKind.distance, ['a', 'b'], [1]),
          c('bc', SketchConstraintKind.distance, ['b', 'c'], [1]),
          c('ac', SketchConstraintKind.distance, ['a', 'c'], [2]),
        ],
      ),
    );
    expect(result.status, SketchSolveStatus.numericalFailure);
    expect(result.diagnostics.first.code, 'singularSolution');
    expect(result.degreesOfFreedom, isNull);
  });

  test(
    'incompatible triangle dimensions conflict independently of initial shape',
    () {
      final result = solver.solve(
        sketch(
          points: [p('a', 0, 0), p('b', 4, 0), p('c', 1, 2)],
          constraints: [
            c('ab', SketchConstraintKind.distance, ['a', 'b'], [5]),
            c('ac', SketchConstraintKind.distance, ['a', 'c'], [1]),
            c('bc', SketchConstraintKind.distance, ['b', 'c'], [1]),
          ],
        ),
      );
      expect(result.status, SketchSolveStatus.conflicting);
      expect(
        result.diagnostics.where((d) => d.constraintId != null),
        hasLength(3),
      );
    },
  );

  test('rigid transformations preserve intrinsic constraints and freedom', () {
    final relations = [
      c('ab', SketchConstraintKind.distance, ['a', 'b'], [4]),
      c('ac', SketchConstraintKind.distance, ['a', 'c'], [3]),
      c('bc', SketchConstraintKind.distance, ['b', 'c'], [5]),
    ];
    for (final angle in [0.0, 0.3, 1.5, math.pi]) {
      final points = [p('a', 0, 0), p('b', 4, 0), p('c', 0, 3)]
          .map(
            (point) => p(
              point.id.value,
              10 + point.x * math.cos(angle) - point.y * math.sin(angle),
              -5 + point.x * math.sin(angle) + point.y * math.cos(angle),
            ),
          )
          .toList();
      final result = solver.solve(
        sketch(points: points, constraints: relations),
      );
      expect(result.status, SketchSolveStatus.underconstrained);
      expect(result.degreesOfFreedom, 3);
      expect(result.geometry!.points.values, points);
    }
  });
}
