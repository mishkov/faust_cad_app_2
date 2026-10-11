import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/constraint_fixtures.dart';

void main() {
  test('all relation kinds encode persistent IDs and explicit references', () {
    final base = sketch(
      points: [p('a', 1, 2), p('b', 4, 3), p('c', 7, 8)],
      lines: [l('ab', 'a', 'b'), l('bc', 'b', 'c')],
      circles: [circle('c1', 'a', 3), circle('c2', 'c', 2)],
    );
    final constraints = [
      c('coincident', SketchConstraintKind.coincident, ['a', 'c']),
      c('onLine', SketchConstraintKind.pointOnLine, ['c', 'ab']),
      c('onCircle', SketchConstraintKind.pointOnCircle, ['b', 'c1']),
      c('h', SketchConstraintKind.horizontal, ['ab']),
      c('v', SketchConstraintKind.vertical, ['bc']),
      c('parallel', SketchConstraintKind.parallel, ['ab', 'bc']),
      c('perpendicular', SketchConstraintKind.perpendicular, ['ab', 'bc']),
      c('length', SketchConstraintKind.lineLength, ['ab'], [4]),
      c('distance', SketchConstraintKind.distance, ['a', 'b'], [5]),
      c('radius', SketchConstraintKind.radius, ['c1'], [3]),
      c('diameter', SketchConstraintKind.diameter, ['c2'], [4]),
      c('equalLengths', SketchConstraintKind.equalLengths, ['ab', 'bc']),
      c('equalRadii', SketchConstraintKind.equalRadii, ['c1', 'c2']),
      c('fixedPoint', SketchConstraintKind.fixedPoint, ['a'], [1, 2]),
      SketchConstraint.fixPrimitive(
        id: SketchConstraintId('fixedLine'),
        sketch: base,
        primitiveId: eid('ab'),
      ),
      SketchConstraint.fixPrimitive(
        id: SketchConstraintId('fixedCircle'),
        sketch: base,
        primitiveId: eid('c1'),
      ),
    ];
    expect(
      constraints.map((c) => c.kind).toSet(),
      SketchConstraintKind.values.toSet(),
    );
    final authored = base.copyWith(constraints: constraints);
    final encoded = authored.toParameters();
    final restored = SketchDefinition.fromParameters(
      support: authored.support,
      parameters: encoded,
    );
    expect(restored, authored);
    expect(restored.constraints.values, constraints);
    expect(restored.constraints[SketchConstraintId('fixedLine')]!.values, [
      1,
      2,
      4,
      3,
    ]);
    expect(restored.constraints[SketchConstraintId('fixedCircle')]!.values, [
      1,
      2,
      3,
    ]);
    expect(
      () => (encoded['constraints'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(() => restored.constraints.clear(), throwsUnsupportedError);
    expect(
      () => restored.constraints.values.first.references.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => restored.constraints.values.first.values.clear(),
      throwsUnsupportedError,
    );
  });

  test('version 1 unconstrained definitions continue to decode', () {
    final original = sketch(points: [p('a', 0, 0)]);
    final version1 = {...original.toParameters(), 'version': 1}
      ..remove('constraints')
      ..remove('retiredConstraintIds');
    expect(
      SketchDefinition.fromParameters(
        support: original.support,
        parameters: version1,
      ),
      original,
    );
    final incomplete = {...original.toParameters()}..remove('constraints');
    expect(
      () => SketchDefinition.fromParameters(
        support: original.support,
        parameters: incomplete,
      ),
      throwsArgumentError,
    );
  });

  test(
    'deletions reserve constraint IDs and retained IDs cannot change kind',
    () {
      final relation = c('h', SketchConstraintKind.horizontal, ['line']);
      final original = sketch(
        points: [p('a', 0, 0), p('b', 2, 1)],
        lines: [l('line', 'a', 'b')],
        constraints: [relation],
      );
      final edited = original.copyWith(
        constraints: [
          c('h', SketchConstraintKind.horizontal, ['line']),
        ],
      );
      expect(edited, original);
      final deleted = original.copyWith(constraints: []);
      expect(deleted.retiredConstraintIds, {SketchConstraintId('h')});
      final restored = SketchDefinition.fromParameters(
        support: deleted.support,
        parameters: deleted.toParameters(),
      );
      expect(
        () => restored.copyWith(constraints: [relation]),
        throwsArgumentError,
      );
      expect(
        () => original.copyWith(
          constraints: [
            c('h', SketchConstraintKind.vertical, ['line']),
          ],
        ),
        throwsArgumentError,
      );
      expect(() => original.copyWith(segments: []), throwsArgumentError);
      final atomic = original.copyWith(segments: [], constraints: []);
      expect(atomic.retiredIds, contains(eid('line')));
      expect(atomic.retiredConstraintIds, contains(SketchConstraintId('h')));
    },
  );

  test('wrong reference kinds missing references duplicate IDs and bad values fail', () {
    final base = sketch(
      points: [p('a', 0, 0), p('b', 1, 0)],
      lines: [l('line', 'a', 'b')],
      circles: [circle('circle', 'a', 1)],
    );
    for (final invalid in [
      c('h', SketchConstraintKind.horizontal, ['a']),
      c('co', SketchConstraintKind.coincident, ['a', 'line']),
      c('on', SketchConstraintKind.pointOnLine, ['a', 'circle']),
      c('on', SketchConstraintKind.pointOnCircle, ['a', 'line']),
      c('distance', SketchConstraintKind.distance, ['a', 'missing'], [1]),
      c('r', SketchConstraintKind.radius, ['line'], [1]),
      c('fixed', SketchConstraintKind.fixedPrimitive, ['circle'], [0, 0, -1]),
      c('fixed', SketchConstraintKind.fixedPrimitive, ['line'], [0, 0, 1]),
    ]) {
      expect(() => base.copyWith(constraints: [invalid]), throwsArgumentError);
    }
    final h = c('h', SketchConstraintKind.horizontal, ['line']);
    expect(() => base.copyWith(constraints: [h, h]), throwsArgumentError);
    for (final kind in [
      SketchConstraintKind.lineLength,
      SketchConstraintKind.radius,
      SketchConstraintKind.diameter,
    ]) {
      expect(() => c('bad', kind, ['line'], [0]), throwsArgumentError);
      expect(
        () => c('bad', kind, ['line'], [double.infinity]),
        throwsArgumentError,
      );
    }
    expect(
      () => c('bad', SketchConstraintKind.distance, ['a', 'b'], [-1]),
      throwsArgumentError,
    );
    expect(
      () => c('bad', SketchConstraintKind.fixedPoint, ['a'], [0]),
      throwsArgumentError,
    );
    expect(() => SketchConstraintId(''), throwsArgumentError);
    expect(
      () => SketchConstraint.fromParameters({
        'id': 'bad',
        'kind': 'unknown',
        'references': [],
        'values': [],
      }),
      throwsArgumentError,
    );
    expect(
      () => SketchConstraint.fromParameters({
        'id': 'bad',
        'kind': 'horizontal',
        'references': [42],
        'values': [],
      }),
      throwsArgumentError,
    );
  });

  test('settings and drag API reject malformed inputs', () {
    for (final policy in [
      () => SketchSolverSettings(distanceTolerance: 0),
      () => SketchSolverSettings(angularTolerance: 1),
      () => SketchSolverSettings(rankTolerance: double.nan),
      () => SketchSolverSettings(maxIterations: -1),
      () => SketchSolverSettings(maxDampingTrials: 0),
    ]) {
      expect(policy, throwsArgumentError);
    }
    final base = sketch(points: [p('a', 0, 0)]);
    expect(
      () => solver.solve(
        base,
        dragTargets: [SketchDragTarget(pointId: eid('missing'), x: 0, y: 0)],
      ),
      throwsArgumentError,
    );
    final target = SketchDragTarget(pointId: eid('a'), x: 1, y: 2);
    expect(
      () => solver.solve(base, dragTargets: [target, target]),
      throwsArgumentError,
    );
  });
}
