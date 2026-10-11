import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../support/sketch_fixtures.dart';

void main() {
  const adapter = SketchPlanarAdapter();

  test('adapts directed segments and analytic circles using authored IDs', () {
    final definition = rectangleSketch(circle: true);
    final inputs = adapter.adapt(definition);
    expect(inputs.map((i) => i.id), [
      'line0',
      'line1',
      'line2',
      'line3',
      'circle',
    ]);
    final segment = inputs.first as PlanarSegment;
    final circle = inputs.last as PlanarCircle;
    expect(segment.start, Vector2(0, 0));
    expect(segment.end, Vector2(4, 0));
    expect(circle.center, Vector2(2, 1.5));
    expect(circle.radius, 0.5);
    segment.start.x = 100;
    circle.center.y = 100;
    expect(segment.start, Vector2.zero());
    expect(circle.center, Vector2(2, 1.5));
    expect(definition.points[entityId('p0')]!.position, Vector2.zero());
    expect(() => inputs.clear(), throwsUnsupportedError);
    expect(adapter.adapt(definition).first, isNot(same(segment)));
  });

  test('one shared point edit updates every referencing boundary and preserves IDs', () {
    final original = rectangleSketch();
    final shared = original.copyWith(
      circles: [
        SketchCircle(
          id: entityId('circle'),
          centerPointId: entityId('p0'),
          radius: 2,
        ),
      ],
    );
    final moved = shared.copyWith(
      points: shared.points.values.map(
        (p) => p.id == entityId('p0') ? SketchPoint(id: p.id, x: -2, y: -3) : p,
      ),
    );
    final inputs = adapter.adapt(moved);
    expect((inputs[0] as PlanarSegment).start, Vector2(-2, -3));
    expect((inputs[3] as PlanarSegment).end, Vector2(-2, -3));
    expect((inputs[4] as PlanarCircle).center, Vector2(-2, -3));
    expect(inputs.map((i) => i.id), adapter.adapt(shared).map((i) => i.id));
  });

  test('region engine consumes adapted profiles with entity provenance after edits', () {
    final original = rectangleSketch(circle: true);
    final before = const PlanarRegionEngine().build(adapter.adapt(original));
    expect(before.isValid, isTrue);
    expect(before.regions, hasLength(2));
    final annulus = before.regions.singleWhere((r) => r.holes.isNotEmpty);
    final reference = before.reference(annulus.id);
    expect(
      annulus.outer.portions
          .expand((p) => p.sources.map((s) => s.inputId))
          .toSet(),
      {'line0', 'line1', 'line2', 'line3'},
    );
    expect(
      annulus.holes.single.portions
          .expand((p) => p.sources.map((s) => s.inputId))
          .toSet(),
      {'circle'},
    );
    final moved = rectangleSketch(width: 6, circle: true);
    final after = const PlanarRegionEngine().build(adapter.adapt(moved));
    expect(after.resolve(reference).status, RegionResolutionStatus.resolved);
    expect(
      after.union(after.regions.map((r) => r.id)).regions.single.area,
      closeTo(18, 1e-10),
    );
  });

  test(
    'isolated points produce no boundaries and degeneracies remain diagnosed',
    () {
      final original = rectangleSketch();
      final isolated = original.copyWith(segments: []);
      expect(adapter.adapt(isolated), isEmpty);
      final zero = original.copyWith(
        segments: [
          SketchLineSegment(
            id: entityId('line0'),
            startPointId: entityId('p0'),
            endPointId: entityId('p0'),
          ),
        ],
      );
      final input = adapter.adapt(zero).single as PlanarSegment;
      expect(input.start, input.end);
      final result = const PlanarRegionEngine().build([input]);
      expect(result.diagnostics.map((d) => d.code), contains('zeroLength'));
    },
  );
}
