import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';

PlanarCircle circle(String id, double x, double y, double r) =>
    PlanarCircle(id: id, center: Vector2(x, y), radius: r);
PlanarSegment line(String id, double x, double y, double u, double v) =>
    PlanarSegment(id: id, start: Vector2(x, y), end: Vector2(u, v));
List<PlanarInput> rectangle(
  String id,
  double x,
  double y,
  double w,
  double h,
) => [
  line('$id:bottom', x, y, x + w, y),
  line('$id:right', x + w, y, x + w, y + h),
  line('$id:top', x + w, y + h, x, y + h),
  line('$id:left', x, y + h, x, y),
];
RegionResult build(List<PlanarInput> inputs) =>
    const PlanarRegionEngine().build(inputs);
RegionSelection all(RegionResult result) =>
    result.union(result.regions.map((r) => r.id));
void usable(RegionResult result) {
  expect(
    result.diagnostics
        .where((d) => d.isError)
        .map((d) => '${d.code}: ${d.message}'),
    isEmpty,
  );
  expect(result.isValid, isTrue);
}

void main() {
  test(
    'normalization cannot close a gap by collapsing distinct input coordinates',
    () {
      final result = build([
        ...rectangle('a', -1, -1, 0.5, 0.5),
        ...rectangle('b', 0, 0, 1, 1),
        ...rectangle('c', 1 + 2.220446049250313e-16, 0, 1, 1),
      ]);
      expect(result.isValid, isFalse);
      expect(result.regions, isEmpty);
      expect(result.diagnostics.map((d) => d.code), contains('numericRange'));
    },
  );

  test('exact diagonal tangency is retained despite normalized coordinate roundoff', () {
    final result = build([circle('a', 0, 0, 5), circle('b', 6, 8, 5)]);
    usable(result);
    expect(result.regions, hasLength(2));
    expect(all(result).isValid, isFalse);
    expect(result.diagnostics.map((d) => d.code), contains('tangency'));
  });

  test(
    'exact predicates keep very small circle gaps and angled line gaps open',
    () {
      final separated = build([
        circle('a', 0, 0, 1),
        circle('b', 2 + 1e-15, 0, 1),
      ]);
      usable(separated);
      expect(all(separated).regions, hasLength(2));
      final open = build([
        line('a', 0, 0, 1, 1),
        line('b', 1, 1, 2, 0),
        line('c', 2, 0, 0.0000000001, 0),
      ]);
      usable(open);
      expect(open.regions, isEmpty);
      expect(open.diagnostics.map((d) => d.code), contains('openBoundary'));
    },
  );

  test(
    'crossed segments and multiway vertices split into four rectangle cells',
    () {
      final result = build([
        ...rectangle('r', -2, -2, 4, 4),
        line('horizontal', -2, 0, 2, 0),
        line('vertical', 0, -2, 0, 2),
      ]);
      usable(result);
      expect(result.regions, hasLength(4));
      for (final r in result.regions) {
        expect(r.area, closeTo(4, 1e-10));
      }
      expect(all(result).regions.single.area, closeTo(16, 1e-10));
      final onlyDiagonal = result.regions
          .where(
            (r) =>
                r.locate(Vector2(-1, -1)) == RegionPointLocation.inside ||
                r.locate(Vector2(1, 1)) == RegionPointLocation.inside,
          )
          .map((r) => r.id);
      expect(result.union(onlyDiagonal).isValid, isFalse);
    },
  );

  test('self-crossing closed inputs expose the two bounded lobes', () {
    final result = build([
      line('a', -1, -1, 1, 1),
      line('b', 1, 1, -1, 1),
      line('c', -1, 1, 1, -1),
      line('d', 1, -1, -1, -1),
    ]);
    usable(result);
    expect(result.regions, hasLength(2));
    expect(result.regions.every((r) => (r.area - 1).abs() < 1e-10), isTrue);
    expect(all(result).isValid, isFalse);
  });

  test(
    'seeded circle arrangements agree with an independent material oracle',
    () {
      for (var seed = 0; seed < 12; seed++) {
        final random = math.Random(seed);
        final circles = List.generate(
          4,
          (i) => circle(
            'c:$i',
            random.nextDouble() * 4 - 2,
            random.nextDouble() * 4 - 2,
            0.5 + random.nextDouble() * 1.5,
          ),
        );
        final result = build(circles);
        usable(result);
        final union = all(result);
        expect(union.isValid, isTrue, reason: 'seed $seed');
        for (var x = -4.0; x <= 4; x += 0.43) {
          for (var y = -4.0; y <= 4; y += 0.47) {
            final p = Vector2(x, y);
            final expected = circles.any(
              (c) => (p - c.center).length < c.radius,
            );
            final cells = result.regions
                .where((r) => r.locate(p) == RegionPointLocation.inside)
                .length;
            expect(cells, expected ? 1 : 0, reason: 'seed $seed at $p');
            expect(
              union.regions.any(
                (r) => r.locate(p) == RegionPointLocation.inside,
              ),
              expected,
              reason: 'union seed $seed at $p',
            );
          }
        }
        expect(
          result.regions.fold(0.0, (a, r) => a + r.area),
          closeTo(union.regions.fold(0.0, (a, r) => a + r.area), 1e-8),
        );
      }
    },
  );

  test(
    'unresolved numerical contact is unavailable, never snapped or guessed',
    () {
      final old = build([circle('a', 0, 0, 1)]);
      final result = build([
        circle('a', 0, 0, 1),
        circle('b', 2 - 1e-15, 0, 1),
      ]);
      expect(result.isValid, isFalse);
      expect(result.regions, isEmpty);
      expect(
        result.diagnostics.map((d) => d.code),
        contains('numericAmbiguity'),
      );
      expect(
        result.resolve(old.reference(old.regions.single.id)).status,
        RegionResolutionStatus.unavailable,
      );
      expect(result.union([]).isValid, isFalse);
      final overflow = build([circle('huge', 0, 0, 1e200)]);
      expect(overflow.isValid, isFalse);
      expect(overflow.regions, isEmpty);
      final underflow = build([circle('tiny', 0, 0, 1e-200)]);
      expect(underflow.isValid, isFalse);
      expect(underflow.regions, isEmpty);
    },
  );

  test(
    'rectangle exposes analytic lines, provenance, area, and point queries',
    () {
      final result = build(rectangle('r', 0, 0, 4, 3));
      usable(result);
      final region = result.regions.single;
      expect(region.area, closeTo(12, 1e-10));
      expect(region.outer.portions, hasLength(4));
      expect(region.outer.portions.every((e) => !e.isArc), isTrue);
      expect(
        region.outer.portions
            .expand((e) => e.sources)
            .map((s) => s.inputId)
            .toSet(),
        {'r:bottom', 'r:top', 'r:left', 'r:right'},
      );
      expect(region.locate(Vector2(1, 1)), RegionPointLocation.inside);
      expect(region.locate(Vector2(4, 1)), RegionPointLocation.boundary);
      expect(region.locate(Vector2(5, 1)), RegionPointLocation.outside);
      expect(all(result).regions.single.area, closeTo(12, 1e-10));
    },
  );

  test(
    'a circle remains analytic and horizontal rays handle extrema and seams',
    () {
      final result = build([circle('c', 0, 0, 2)]);
      usable(result);
      final region = result.regions.single;
      expect(region.area, closeTo(4 * math.pi, 1e-10));
      expect(region.outer.portions.every((e) => e.isArc), isTrue);
      final sources = region.outer.portions.expand((e) => e.sources).toList();
      expect(
        sources
            .map((s) => (s.endParameter - s.startParameter).abs())
            .reduce((a, b) => a + b),
        closeTo(2 * math.pi, 1e-12),
      );
      for (final p in [
        Vector2.zero(),
        Vector2(1, 0),
        Vector2(0, 1),
        Vector2(-1, 0),
        Vector2(0, -1),
      ]) {
        expect(region.locate(p), RegionPointLocation.inside);
      }
      expect(
        region.locate(Vector2(0, 2), boundaryDistance: 1e-12),
        RegionPointLocation.boundary,
      );
      expect(region.locate(Vector2(-3, 2)), RegionPointLocation.outside);
    },
  );

  test(
    'overlapping circles expose three cells; all union to one analytic profile',
    () {
      final result = build([circle('a', 0, 0, 2), circle('b', 2, 0, 2)]);
      usable(result);
      expect(result.regions, hasLength(3));
      final lensArea = 8 * math.pi / 3 - 2 * math.sqrt(3);
      final union = all(result);
      expect(union.isValid, isTrue);
      expect(union.regions, hasLength(1));
      expect(union.regions.single.area, closeTo(8 * math.pi - lensArea, 1e-9));
      expect(union.regions.single.outer.portions.every((e) => e.isArc), isTrue);
      expect(
        result.regions.where(
          (r) => r.locate(Vector2(1, 0)) == RegionPointLocation.inside,
        ),
        hasLength(1),
      );
      expect(
        result.regions.map((r) => r.area).reduce((a, b) => a + b),
        closeTo(union.regions.single.area, 1e-10),
      );
    },
  );

  test('circle with diameter splits into two semicircular material cells', () {
    final result = build([circle('c', 0, 0, 2), line('diameter', -2, 0, 2, 0)]);
    usable(result);
    expect(result.regions, hasLength(2));
    for (final r in result.regions) {
      expect(r.area, closeTo(2 * math.pi, 1e-10));
    }
    final union = all(result);
    expect(union.regions, hasLength(1));
    expect(union.regions.single.outer.portions.every((p) => p.isArc), isTrue);
  });

  test(
    'shared boundary segments cancel in union including opposite directions',
    () {
      final result = build([
        ...rectangle('a', 0, 0, 2, 2),
        ...rectangle('b', 2, 0, 2, 2),
      ]);
      usable(result);
      expect(result.regions, hasLength(2));
      final shared = result.regions
          .expand((r) => r.outer.portions)
          .where((p) => p.sources.length == 2)
          .toList();
      expect(shared, hasLength(2));
      expect(
        shared.first.sources
            .map((s) => s.endParameter - s.startParameter)
            .reduce((a, b) => a + b),
        closeTo(0, 1e-12),
      );
      expect(all(result).regions.single.area, closeTo(8, 1e-10));
    },
  );

  test(
    'partial shared boundaries and overlapping rectangles form material union',
    () {
      for (final inputs in [
        [...rectangle('a', 0, 0, 3, 3), ...rectangle('b', 3, 1, 2, 1)],
        [...rectangle('a', 0, 0, 3, 3), ...rectangle('b', 2, 1, 2, 1)],
      ]) {
        final result = build(inputs);
        usable(result);
        final union = all(result);
        expect(union.isValid, isTrue);
        expect(union.regions, hasLength(1));
        expect(
          union.regions.single.area,
          closeTo(
            inputs[4] is PlanarSegment &&
                    (inputs[4] as PlanarSegment).start.x == 3
                ? 11
                : 10,
            1e-9,
          ),
        );
      }
    },
  );

  test('an intentional gap smaller than tolerance never merges profiles', () {
    final result = build([
      ...rectangle('a', 0, 0, 1, 1),
      ...rectangle('b', 1 + 1e-10, 0, 1, 1),
    ]);
    usable(result);
    expect(result.regions, hasLength(2));
    expect(all(result).regions, hasLength(2));
  });

  test('a nearly closed rectangle remains an open chain', () {
    final inputs = rectangle('r', 0, 0, 1, 1);
    inputs[3] = line('r:left', 0, 1, 0, 1e-10);
    final result = build(inputs);
    usable(result);
    expect(result.regions, isEmpty);
    expect(result.diagnostics.map((d) => d.code), contains('openBoundary'));
  });

  test(
    'concentric circles expose disk and annulus; selecting both fills hole',
    () {
      final result = build([
        circle('outer', 0, 0, 3),
        circle('inner', 0, 0, 1),
      ]);
      usable(result);
      expect(result.regions, hasLength(2));
      final disk = result.regions.singleWhere((r) => r.holes.isEmpty);
      final annulus = result.regions.singleWhere((r) => r.holes.isNotEmpty);
      expect(disk.area, closeTo(math.pi, 1e-10));
      expect(annulus.area, closeTo(8 * math.pi, 1e-10));
      expect(annulus.locate(Vector2.zero()), RegionPointLocation.outside);
      expect(annulus.locate(Vector2(2, 0)), RegionPointLocation.inside);
      expect(result.union([annulus.id]).regions.single.holes, hasLength(1));
      final filled = all(result).regions.single;
      expect(filled.holes, isEmpty);
      expect(filled.area, closeTo(9 * math.pi, 1e-10));
    },
  );

  test('three-level nesting and independent holes', () {
    final result = build([
      circle('a', 0, 0, 5),
      circle('b', 0, 0, 3),
      circle('c', 0, 0, 1),
    ]);
    usable(result);
    expect(result.regions, hasLength(3));
    expect(result.regions.where((r) => r.holes.isNotEmpty), hasLength(2));
    expect(all(result).regions.single.area, closeTo(25 * math.pi, 1e-9));
    final multiple = build([
      ...rectangle('box', -5, -5, 10, 10),
      circle('left', -2, 0, 1),
      circle('right', 2, 0, 1),
    ]);
    usable(multiple);
    final pierced = multiple.regions.singleWhere((r) => r.holes.length == 2);
    expect(pierced.area, closeTo(100 - 2 * math.pi, 1e-9));
    expect(multiple.union([pierced.id]).regions.single.holes, hasLength(2));
  });

  test(
    'duplicate/reversed segments and coincident circles retain all provenance',
    () {
      final result = build([
        ...rectangle('r', 0, 0, 2, 2),
        line('duplicate', 2, 0, 0, 0),
        line('overlap', 0.5, 0, 1.5, 0),
      ]);
      usable(result);
      expect(result.regions, hasLength(1));
      expect(result.regions.single.area, closeTo(4, 1e-10));
      final triple = result.regions.single.outer.portions.singleWhere(
        (p) => p.sources.length == 3,
      );
      final reverse = triple.sources.singleWhere(
        (s) => s.inputId == 'duplicate',
      );
      expect(reverse.endParameter, lessThan(reverse.startParameter));
      final circular = build([circle('a', 0, 0, 2), circle('b', 0, 0, 2)]);
      usable(circular);
      expect(circular.regions, hasLength(1));
      expect(
        circular.regions.single.outer.portions.every(
          (p) => p.sources.length == 2,
        ),
        isTrue,
      );
      expect(
        circular.diagnostics.map((d) => d.code),
        contains('coincidentCircle'),
      );
    },
  );

  test(
    'point-only rectangle contact rejects union but each alone is valid',
    () {
      final result = build([
        ...rectangle('a', 0, 0, 1, 1),
        ...rectangle('b', 1, 1, 1, 1),
      ]);
      usable(result);
      expect(result.regions, hasLength(2));
      expect(all(result).isValid, isFalse);
      expect(all(result).diagnostics.single.code, 'nonManifoldSelection');
      expect(all(result).regions, isEmpty);
      expect(result.union([result.regions.first.id]).isValid, isTrue);
    },
  );

  test(
    'external circle tangency exposes disks and rejects point-connected union',
    () {
      final result = build([circle('a', 0, 0, 1), circle('b', 2, 0, 1)]);
      usable(result);
      expect(result.regions, hasLength(2));
      expect(result.diagnostics.map((d) => d.code), contains('tangency'));
      expect(all(result).isValid, isFalse);
      for (final r in result.regions) {
        expect(r.area, closeTo(math.pi, 1e-10));
      }
    },
  );

  test('internal circle tangency preserves touching hole but rejects extrusion selection', () {
    final result = build([circle('a', 0, 0, 2), circle('b', 1, 0, 1)]);
    usable(result);
    expect(result.regions, hasLength(2));
    final annulus = result.regions.singleWhere((r) => r.holes.isNotEmpty);
    expect(annulus.area, closeTo(3 * math.pi, 1e-10));
    expect(result.union([annulus.id]).isValid, isFalse);
    expect(all(result).isValid, isTrue);
    expect(all(result).regions.single.area, closeTo(4 * math.pi, 1e-10));
  });

  test('tangent open segment never creates or removes circle material', () {
    final result = build([circle('c', 0, 0, 1), line('t', -2, 1, 2, 1)]);
    usable(result);
    expect(result.regions, hasLength(1));
    expect(result.regions.single.area, closeTo(math.pi, 1e-10));
    expect(
      result.diagnostics.map((d) => d.code),
      containsAll(['tangency', 'openBoundary']),
    );
  });

  test(
    'dangling chains and bridges between profiles contribute no false holes',
    () {
      final result = build([
        ...rectangle('a', 0, 0, 1, 1),
        ...rectangle('b', 3, 0, 1, 1),
        line('bridge', 1, 0, 3, 0),
        line('tail', -2, 0, 0, 0),
      ]);
      usable(result);
      expect(result.regions, hasLength(2));
      expect(all(result).regions, hasLength(2));
      expect(result.diagnostics.map((d) => d.code), contains('openBoundary'));
    },
  );

  test('tiny geometry is retained and translations preserve area', () {
    for (final inputs in [
      rectangle('tiny', 0, 0, 1e-12, 2e-12),
      [circle('tiny', 0, 0, 1e-12)],
    ]) {
      final result = build(inputs);
      usable(result);
      expect(result.regions, hasLength(1));
      expect(result.regions.single.area, greaterThan(0));
      expect(result.diagnostics.map((d) => d.code), contains('tinyGeometry'));
    }
    final shifted = build(rectangle('r', 1e12, -1e12, 4, 3));
    usable(shifted);
    expect(shifted.regions.single.area, closeTo(12, 1e-10));
  });

  test('results, IDs, diagnostics and provenance are independent of input order', () {
    final inputs = [
      ...rectangle('box', -3, -3, 6, 6),
      circle('a', -0.5, 0, 2),
      circle('b', 0.5, 0, 2),
      line('cut', -3, 0, 3, 0),
    ];
    String fingerprint(RegionResult result) => result.regions
        .map(
          (r) =>
              '${r.id}:${r.area}:${r.holes.length}:${r.outer.portions.map((p) => p.sources.map((s) => '${s.inputId}:${s.startParameter}:${s.endParameter}').join('|')).join(';')}',
        )
        .join('\n');
    final baseline = build(inputs);
    usable(baseline);
    for (var i = 0; i < 8; i++) {
      final shuffled = inputs.toList()..shuffle(math.Random(i));
      final result = build(shuffled);
      usable(result);
      expect(fingerprint(result), fingerprint(baseline));
    }
  });

  test('references retain semantic IDs across edits and explicitly report ambiguity', () {
    final old = build(rectangle('r', 0, 0, 2, 2));
    final reference = old.reference(old.regions.single.id);
    expect(old.resolve(reference).status, RegionResolutionStatus.resolved);
    final moved = build(rectangle('r', 5, 5, 3, 3));
    expect(moved.resolve(reference).status, RegionResolutionStatus.resolved);
    expect(
      build(rectangle('other', 0, 0, 2, 2)).resolve(reference).status,
      RegionResolutionStatus.missing,
    );
    final overlap = build([circle('a', 0, 0, 2), circle('b', 2, 0, 2)]);
    final ref = overlap.reference(overlap.regions.first.id);
    expect(overlap.resolve(ref).status, RegionResolutionStatus.resolved);
    final edited = build([circle('a', 0, 0, 3), circle('b', 2, 0, 3)]);
    expect(edited.resolve(ref).status, RegionResolutionStatus.ambiguous);
    expect(edited.resolve(ref).candidates, hasLength(3));
  });

  test('input validation, empty selections, and mutation isolation', () {
    final center = Vector2.zero();
    final input = PlanarCircle(id: 'c', center: center, radius: 1);
    center.x = 100;
    input.center.y = 100;
    final result = build([input]);
    expect(
      result.regions.single.locate(Vector2.zero()),
      RegionPointLocation.inside,
    );
    result.regions.single.outer.portions.first.center!.x = 100;
    expect(result.regions.single.area, closeTo(math.pi, 1e-10));
    expect(() => result.regions.clear(), throwsUnsupportedError);
    expect(
      () => result.regions.single.outer.portions.clear(),
      throwsUnsupportedError,
    );
    expect(() => build([input, input]), throwsArgumentError);
    expect(() => circle('', 0, 0, 1), throwsArgumentError);
    expect(() => circle('bad', 0, 0, 0), throwsArgumentError);
    expect(() => line('bad', double.nan, 0, 1, 0), throwsArgumentError);
    expect(() => result.union(['missing']), throwsArgumentError);
    expect(result.union([]).regions, isEmpty);
    expect(build([]).regions, isEmpty);
    expect(
      build([line('zero', 0, 0, 0, 0)]).diagnostics.single.code,
      'zeroLength',
    );
  });
}
