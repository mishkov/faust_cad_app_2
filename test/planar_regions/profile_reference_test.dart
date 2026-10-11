import 'dart:convert';
import 'dart:math' as math;

import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../support/extrusion_fixtures.dart';

const source = 'sketch:profiles';
ProfileReference capture(RegionResult result, PlanarRegion cell) {
  final captured = result.captureProfile(cell.id, sourceId: source);
  expect(captured.status, RegionResolutionStatus.resolved);
  return ProfileReference.fromJson(
    jsonDecode(jsonEncode(captured.reference!.toJson()))
        as Map<String, Object?>,
  );
}

PlanarRegion at(RegionResult result, double x, double y) => result.regions
    .singleWhere((r) => r.locate(Vector2(x, y)) == RegionPointLocation.inside);
RegionResolution resolve(RegionResult result, ProfileReference reference) =>
    result.resolveProfile(reference, sourceId: source);

void main() {
  test(
    'disk and annulus persist through independent sizes and placement edits',
    () {
      final before = profileArrangement([
        profileCircle('outer', 0, 0, 4),
        profileCircle('inner', 0, 0, 1),
      ]);
      final disk = capture(before, at(before, 0, 0));
      final annulus = capture(before, at(before, 2, 0));
      expect(disk, isNot(annulus));
      final after = profileArrangement([
        profileCircle('inner', 7, -3, 2),
        profileCircle('outer', 7, -3, 6),
      ]);
      expect(resolve(after, disk).candidates.single, at(after, 7, -3));
      expect(resolve(after, annulus).candidates.single, at(after, 10, -3));
      final filled = ProfileSelectionReference([disk, annulus]);
      final selected = after.resolveProfiles(filled, sourceId: source);
      expect(selected.status, RegionResolutionStatus.resolved);
      expect(selected.material!.regions.single.holes, isEmpty);
    },
  );

  test('lens and both crescents are distinct after rotation and unequal radius edits', () {
    final before = profileArrangement([
      profileCircle('a', 0, 0, 2),
      profileCircle('b', 2, 0, 2),
    ]);
    final refs = [
      for (final x in [-1.0, 1.0, 3.0]) capture(before, at(before, x, 0)),
    ];
    expect(refs.toSet(), hasLength(3));
    // Rotate the center line across the engine's arbitrary angular seams.
    final after = profileArrangement([
      profileCircle('b', 10, 13, 2.5),
      profileCircle('a', 10, 10, 3),
    ]);
    final queries = [Vector2(10, 8), Vector2(10, 11.5), Vector2(10, 15)];
    for (var i = 0; i < refs.length; i++) {
      final current = resolve(after, refs[i]);
      expect(current.status, RegionResolutionStatus.resolved);
      expect(
        current.candidates.single.locate(queries[i]),
        RegionPointLocation.inside,
      );
      expect(capture(after, current.candidates.single), refs[i]);
    }
  });

  test(
    'line-circle branch lineage preserves both half disks through edits',
    () {
      final before = profileArrangement([
        profileCircle('c', 0, 0, 2),
        profileLine('cut', -2, 0, 2, 0),
      ]);
      final upper = capture(before, at(before, 0, 1));
      final lower = capture(before, at(before, 0, -1));
      final after = profileArrangement([
        profileCircle('c', 10, 5, 3),
        profileLine('cut', 10, 2, 10, 8),
      ]);
      expect(resolve(after, upper).candidates.single, at(after, 9, 5));
      expect(resolve(after, lower).candidates.single, at(after, 11, 5));
    },
  );

  test(
    'rectangle references preserve authored endpoints and input permutation',
    () {
      final before = profileArrangement(profileRectangle('box', 0, 0, 2, 3));
      final ref = capture(before, before.regions.single);
      final inputs = profileRectangle('box', 10, -5, 7, 1);
      for (var i = 0; i < 6; i++) {
        final after = profileArrangement(
          inputs.toList()..shuffle(math.Random(i)),
        );
        expect(resolve(after, ref).status, RegionResolutionStatus.resolved);
        expect(capture(after, after.regions.single), ref);
      }
      expect(
        resolve(
          before,
          ProfileReference(sourceId: 'other-sketch', signature: ref.signature),
        ).status,
        RegionResolutionStatus.missing,
      );
      final reversed = inputs.map((p) {
        final line = p as PlanarSegment;
        return PlanarSegment(id: line.id, start: line.end, end: line.start);
      });
      expect(
        resolve(profileArrangement(reversed), ref).status,
        RegionResolutionStatus.missing,
      );
    },
  );

  test(
    'disconnected references survive unrelated component addition and deletion',
    () {
      final before = profileArrangement([
        profileCircle('z', 0, 0, 1),
        profileCircle('m', 5, 0, 1),
      ]);
      final z = capture(before, at(before, 0, 0));
      final m = capture(before, at(before, 5, 0));
      final after = profileArrangement([
        profileCircle('a', -10, 0, 1),
        profileCircle('z', 0, 0, 2),
      ]);
      expect(resolve(after, z).status, RegionResolutionStatus.resolved);
      expect(resolve(after, m).status, RegionResolutionStatus.missing);
      final selected = after.resolveProfiles(
        ProfileSelectionReference([z, m]),
        sourceId: source,
      );
      expect(selected.status, RegionResolutionStatus.missing);
      expect(selected.regions, isEmpty);
      expect(selected.material, isNull);
    },
  );

  test(
    'splitting and merging retire the former cells without selecting neighbors',
    () {
      final disk = profileArrangement([profileCircle('c', 0, 0, 2)]);
      final old = capture(disk, disk.regions.single);
      final split = profileArrangement([
        profileCircle('c', 0, 0, 2),
        profileLine('cut', -3, 0, 3, 0),
      ]);
      expect(resolve(split, old).status, RegionResolutionStatus.missing);
      for (final cell in split.regions) {
        expect(
          resolve(disk, capture(split, cell)).status,
          RegionResolutionStatus.missing,
        );
      }
      final overlap = profileArrangement([
        profileCircle('a', 0, 0, 2),
        profileCircle('b', 2, 0, 2),
      ]);
      for (final next in [
        profileArrangement([
          profileCircle('a', 0, 0, 2),
          profileCircle('b', 5, 0, 2),
        ]),
        profileArrangement([
          profileCircle('a', 0, 0, 3),
          profileCircle('b', 0, 0, 1),
        ]),
      ]) {
        for (final cell in overlap.regions) {
          expect(
            resolve(next, capture(overlap, cell)).status,
            RegionResolutionStatus.missing,
          );
        }
      }
    },
  );

  test('invalid and unsupported correspondence are explicitly unavailable', () {
    final old = profileArrangement([profileCircle('c', 0, 0, 2)]);
    final ref = capture(old, old.regions.single);
    final invalid = profileArrangement([
      profileCircle('c', 0, 0, 1),
      profileCircle('d', 2 - 1e-15, 0, 1),
    ]);
    expect(invalid.isValid, isFalse);
    expect(resolve(invalid, ref).status, RegionResolutionStatus.unavailable);
    final p = old.regions.single.outer.portions.first;
    final unknown = PlanarRegion(
      id: 'unknown',
      outer: RegionLoop([
        BoundaryPortion.arc(
          center: p.center!,
          radius: p.radius!,
          startAngle: 0,
          sweepAngle: 2 * math.pi,
          sources: p.sources,
        ),
      ]),
    );
    final unsupported = RegionResult(
      regions: [unknown],
      diagnostics: [],
      select: (_) => RegionSelection([], []),
    );
    expect(
      unsupported.captureProfile('unknown', sourceId: source).status,
      RegionResolutionStatus.unavailable,
    );
    expect(
      resolve(unsupported, ref).status,
      RegionResolutionStatus.unavailable,
    );
    final unrelated = PlanarRegion(
      id: 'unrelated',
      outer: RegionLoop([
        BoundaryPortion.arc(
          center: Vector2(10, 0),
          radius: 1,
          startAngle: 0,
          sweepAngle: 2 * math.pi,
          sources: [const BoundarySource('other', 0, 2 * math.pi)],
        ),
      ]),
    );
    final mixed = RegionResult(
      regions: [old.regions.single, unrelated],
      diagnostics: [],
      select: (_) => RegionSelection([], []),
    );
    expect(resolve(mixed, ref).status, RegionResolutionStatus.resolved);
    final unproven = RegionResult(
      regions: [
        PlanarRegion(
          id: 'unproven',
          outer: RegionLoop([
            BoundaryPortion.arc(
              center: Vector2.zero(),
              radius: 2,
              startAngle: 0,
              sweepAngle: 2 * math.pi,
              sources: [],
              lineage: const BoundaryLineage(
                start: 'unsupported',
                end: 'unsupported',
              ),
            ),
          ]),
        ),
      ],
      diagnostics: [],
      select: (_) => RegionSelection([], []),
    );
    expect(resolve(unproven, ref).status, RegionResolutionStatus.unavailable);
    final malformed = RegionResult(
      regions: [
        PlanarRegion(
          id: 'malformed',
          outer: RegionLoop([
            BoundaryPortion.arc(
              center: Vector2.zero(),
              radius: 2,
              startAngle: 0,
              sweepAngle: 2 * math.pi,
              sources: p.sources,
              lineage: const BoundaryLineage(
                start: 'unsupported',
                end: 'unsupported',
              ),
            ),
          ]),
        ),
      ],
      diagnostics: [],
      select: (_) => RegionSelection([], []),
    );
    expect(
      malformed.captureProfile('malformed', sourceId: source).status,
      RegionResolutionStatus.unavailable,
    );
    expect(
      old.captureProfile('deleted', sourceId: source).status,
      RegionResolutionStatus.missing,
    );
  });

  test(
    'duplicate semantic candidates are ambiguous even within a snapshot',
    () {
      final original = profileArrangement(profileRectangle('r', 0, 0, 2, 3));
      final ref = capture(original, original.regions.single);
      final cell = original.regions.single;
      final duplicate = RegionResult(
        regions: [
          cell,
          PlanarRegion(id: 'second', outer: cell.outer),
        ],
        diagnostics: [],
        select: (_) => RegionSelection([], []),
      );
      expect(resolve(duplicate, ref).status, RegionResolutionStatus.ambiguous);
      expect(resolve(duplicate, ref).candidates, hasLength(2));
      expect(
        duplicate.captureProfile(cell.id, sourceId: source).reference,
        isNull,
      );
      expect(
        duplicate
            .resolveProfiles(ProfileSelectionReference([ref]), sourceId: source)
            .regions,
        isEmpty,
      );
    },
  );

  test(
    'selection serializes into document parameters with no snapshot IDs',
    () {
      final original = profileArrangement(profileRectangle('box', 0, 0, 2, 3));
      final reference = capture(original, original.regions.single);
      final selection = ProfileSelectionReference([reference, reference]);
      final definition = FeatureDefinition(
        id: FeatureId('consumer'),
        type: 'test-consumer',
        parameters: {'profile': selection.toJson()},
      );
      final stored = jsonEncode(definition.parameters);
      expect(stored, isNot(contains('region:')));
      expect(stored, isNot(contains('union:')));
      final decoded = jsonDecode(stored) as Map<String, Object?>;
      final frozen = definition.parameters['profile'] as Map<String, Object?>;
      final frozenProfile =
          (frozen['profiles'] as List).single as Map<String, Object?>;
      expect(
        ProfileLineage.canonicalSignature(frozenProfile['signature']),
        reference.signature,
      );
      final restored = ProfileSelectionReference.fromJson(
        decoded['profile'] as Map<String, Object?>,
      );
      expect(restored, selection);
      final after = profileArrangement(profileRectangle('box', 4, 7, 5, 6));
      expect(
        after.resolveProfiles(restored, sourceId: source).status,
        RegionResolutionStatus.resolved,
      );
      expect(() => restored.references.clear(), throwsUnsupportedError);
      expect(
        () => ProfileReference.fromJson({'version': 2, 'sourceId': source}),
        throwsFormatException,
      );
      expect(
        () => ProfileReference.fromJson({
          'version': 1,
          'sourceId': source,
          'signature': ['region:0', []],
        }),
        throwsFormatException,
      );
      expect(() => ProfileSelectionReference([]), throwsArgumentError);
      final encoded = reference.toJson();
      (encoded['signature'] as List).clear();
      expect(resolve(after, reference).status, RegionResolutionStatus.resolved);
    },
  );

  test('atomic reference selection rejects point-connected material', () {
    final result = profileArrangement([
      profileCircle('a', 0, 0, 1),
      profileCircle('b', 2, 0, 1),
    ]);
    final selected = result.resolveProfiles(
      ProfileSelectionReference(result.regions.map((r) => capture(result, r))),
      sourceId: source,
    );
    expect(selected.status, RegionResolutionStatus.unavailable);
    expect(selected.regions, isEmpty);
  });
}
