import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../support/sketch_fixtures.dart';

void main() {
  const support = PlanarSupport.principal(PrincipalPlane.xy);

  test('local points and all public collections are immutable values', () {
    final source = [SketchPoint(id: entityId('p'), x: 1, y: 2)];
    final retired = {entityId('old')};
    final definition = SketchDefinition(
      support: support,
      points: source,
      retiredIds: retired,
    );
    source.clear();
    retired.clear();
    definition.points[entityId('p')]!.position.x = 20;
    expect(definition.points[entityId('p')]!.position, Vector2(1, 2));
    expect(definition.retiredIds, {entityId('old')});
    expect(() => definition.points.clear(), throwsUnsupportedError);
    expect(() => definition.segments.clear(), throwsUnsupportedError);
    expect(() => definition.circles.clear(), throwsUnsupportedError);
    expect(() => definition.retiredIds.clear(), throwsUnsupportedError);
    final encoded = definition.toParameters();
    expect(() => encoded.clear(), throwsUnsupportedError);
    expect(() => (encoded['points'] as List).clear(), throwsUnsupportedError);
    expect(
      () => ((encoded['points'] as List).single as Map)['x'] = 20,
      throwsUnsupportedError,
    );
    expect(
      SketchDefinition.fromParameters(support: support, parameters: encoded),
      definition,
    );
  });

  test(
    'edits and reordered collections preserve independent entity identities',
    () {
      final original = rectangleSketch(circle: true);
      final moved = original.copyWith(
        points: original.points.values.toList().reversed.map(
          (p) => SketchPoint(id: p.id, x: p.x + 10, y: p.y - 3),
        ),
        circles: [
          SketchCircle(
            id: entityId('circle'),
            centerPointId: entityId('center'),
            radius: 2,
          ),
        ],
        support: const PlanarSupport.principal(PrincipalPlane.yz),
      );
      expect(moved.points.keys.toSet(), original.points.keys.toSet());
      expect(moved.segments, original.segments);
      expect(moved.circles.keys, original.circles.keys);
      expect(moved.retiredIds, isEmpty);
      expect(original.points[entityId('p0')]!.position, Vector2.zero());
      expect(moved.points[entityId('p0')]!.position, Vector2(10, -3));
      expect(moved.support.principalPlane, PrincipalPlane.yz);
      final coincident = SketchDefinition(
        support: support,
        points: [
          SketchPoint(id: entityId('a'), x: 0, y: 0),
          SketchPoint(id: entityId('b'), x: 0, y: 0),
        ],
      );
      expect(coincident.points, hasLength(2));
    },
  );

  test('deleted IDs are reserved across edits and parameter round trips', () {
    final original = rectangleSketch(circle: true);
    final deleted = original.copyWith(circles: []);
    final restoredValue = SketchDefinition.fromParameters(
      support: support,
      parameters: deleted.toParameters(),
    );
    expect(restoredValue.retiredIds, {entityId('circle')});
    expect(
      () => restoredValue.copyWith(circles: original.circles.values),
      throwsArgumentError,
    );
    expect(
      () => restoredValue.copyWith(
        points: [
          ...restoredValue.points.values,
          SketchPoint(id: entityId('circle'), x: 50, y: 50),
        ],
      ),
      throwsArgumentError,
    );
    final fresh = restoredValue.copyWith(
      circles: [
        SketchCircle(
          id: entityId('new-circle'),
          centerPointId: entityId('center'),
          radius: 1,
        ),
      ],
    );
    expect(fresh.circles.keys.single, entityId('new-circle'));
    expect(fresh.retiredIds, {entityId('circle')});
    expect(original.circles, hasLength(1));
  });

  test(
    'retained IDs cannot change kind even in a simultaneous replacement',
    () {
      final original = rectangleSketch(circle: true);
      expect(
        () => original.copyWith(
          circles: [],
          segments: [
            ...original.segments.values,
            SketchLineSegment(
              id: entityId('circle'),
              startPointId: entityId('p0'),
              endPointId: entityId('p1'),
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('deleting points requires updating every reference atomically', () {
    final original = rectangleSketch(circle: true);
    final points = original.points.values.where(
      (p) => p.id != entityId('center'),
    );
    expect(() => original.copyWith(points: points), throwsArgumentError);
    final deleted = original.copyWith(points: points, circles: []);
    expect(deleted.retiredIds, {entityId('center'), entityId('circle')});
    expect(
      () => original.copyWith(
        points: original.points.values.where((p) => p.id != entityId('p0')),
      ),
      throwsArgumentError,
    );
  });

  test('IDs are nonempty and unique across all entity kinds', () {
    expect(() => SketchEntityId(''), throwsArgumentError);
    final p = SketchPoint(id: entityId('p'), x: 0, y: 0);
    expect(
      () => SketchDefinition(support: support, points: [p, p]),
      throwsArgumentError,
    );
    final s = SketchLineSegment(
      id: entityId('s'),
      startPointId: p.id,
      endPointId: p.id,
    );
    expect(
      () => SketchDefinition(support: support, points: [p], segments: [s, s]),
      throwsArgumentError,
    );
    final c = SketchCircle(id: entityId('c'), centerPointId: p.id, radius: 1);
    expect(
      () => SketchDefinition(support: support, points: [p], circles: [c, c]),
      throwsArgumentError,
    );
    expect(
      () => SketchDefinition(
        support: support,
        points: [p],
        circles: [SketchCircle(id: p.id, centerPointId: p.id, radius: 1)],
      ),
      throwsArgumentError,
    );
    expect(
      () => SketchDefinition(support: support, points: [p], retiredIds: {p.id}),
      throwsArgumentError,
    );
  });

  test('segments and circles must reference existing points', () {
    final p = SketchPoint(id: entityId('p'), x: 0, y: 0);
    for (final start in [p.id, entityId('missing')]) {
      expect(
        () => SketchDefinition(
          support: support,
          points: [p],
          segments: [
            SketchLineSegment(
              id: entityId('line'),
              startPointId: start,
              endPointId: entityId('missing'),
            ),
          ],
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => SketchDefinition(
        support: support,
        circles: [
          SketchCircle(id: entityId('circle'), centerPointId: p.id, radius: 1),
        ],
      ),
      throwsArgumentError,
    );
  });

  test(
    'points and circle dimensions reject nonfinite or nonpositive values',
    () {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => SketchPoint(id: entityId('p'), x: bad, y: 0),
          throwsArgumentError,
        );
        expect(
          () => SketchPoint(id: entityId('p'), x: 0, y: bad),
          throwsArgumentError,
        );
      }
      for (final bad in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => SketchCircle(
            id: entityId('c'),
            centerPointId: entityId('p'),
            radius: bad,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'malformed parameters fail validation rather than dropping entities',
    () {
      final good = rectangleSketch(circle: true).toParameters();
      for (final bad in [
        null,
        {},
        {...good, 'version': 3},
        {
          ...good,
          'points': [
            {'id': 'p', 'x': 'zero', 'y': 0},
          ],
        },
        {
          ...good,
          'points': [
            {'id': 'p', 'x': double.nan, 'y': 0},
          ],
        },
        {
          ...good,
          'segments': [
            {'id': 's', 'start': 'p0'},
          ],
        },
        {
          ...good,
          'segments': [
            {'id': 's', 'start': 'p0', 'end': 'missing'},
          ],
        },
        {
          ...good,
          'circles': [
            {'id': 'c', 'center': 'center'},
          ],
        },
        {
          ...good,
          'circles': [
            {'id': 'c', 'center': 'center', 'radius': -1},
          ],
        },
        {
          ...good,
          'retiredIds': [42],
        },
        {
          ...good,
          'retiredIds': ['circle'],
        },
      ]) {
        expect(
          () => SketchDefinition.fromParameters(
            support: support,
            parameters: bad,
          ),
          throwsArgumentError,
        );
      }
    },
  );
}
