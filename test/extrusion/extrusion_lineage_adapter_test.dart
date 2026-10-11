import 'dart:convert';
import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/evaluation_snapshot.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/planar_support_resolution.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../support/extrusion_fixtures.dart';

final producer = FeatureId('extrusion-producer');
ExtrusionLineageResult adapt(
  RegionResult arrangement, {
  Iterable<String>? ids,
  double distance = 3,
  bool reverse = false,
  PlanarFrame? frame,
}) {
  final extrusion = const AnalyticExtrusionService().extrude(
    regions: arrangement,
    regionIds: ids ?? arrangement.regions.map((r) => r.id),
    frame: frame ?? PlanarFrame.xy(),
    distance: distance,
    reverse: reverse,
  );
  expect(
    extrusion.isValid,
    isTrue,
    reason: extrusion.diagnostics.map((d) => d.message).join('\n'),
  );
  return const ExtrusionLineageAdapter().adapt(
    featureId: producer,
    profileSourceId: 'sketch:profiles',
    extrusion: extrusion,
  );
}

String role(OutputReference ref) => (jsonDecode(ref.key) as List)[3] as String;
EvaluationSnapshot snapshot(ExtrusionLineageResult result) =>
    EvaluationSnapshot(
      revision: 1,
      features: {
        producer: FeatureResult(
          state: FeatureState.valid,
          outputs: result.outputs,
        ),
      },
      evaluationOrder: [producer],
      rebuiltFeatures: {producer},
    );

void main() {
  test('rectangle body, caps and walls survive ordinary edits and reverse', () {
    final before = adapt(
      profileArrangement(profileRectangle('box', 0, 0, 2, 3)),
    );
    expect(before.outputs, hasLength(7));
    final after = adapt(
      profileArrangement(profileRectangle('box', 6, -4, 5, 7)),
      distance: 8,
      reverse: true,
      frame: PlanarFrame.xz(origin: Vector3(3, 4, 5)),
    );
    for (final ref in before.references) {
      expect(after.resolve(ref).status, ReferenceStatus.resolved);
      expect(snapshot(after).resolve(ref).status, ReferenceStatus.resolved);
      expect(ref.key, isNot(contains('union:')));
      expect(ref.key, isNot(contains('volume:')));
    }
    expect(after.unavailableFaces, isEmpty);
    expect(snapshot(after).materializeGeometry().faces, hasLength(6));
    final endCap = before.references.singleWhere((r) => role(r) == 'endCap');
    final support = PlanarSupportResolution.resolve(
      PlanarSupport.face(
        reference: endCap,
        preferredDirection: Vector3(1, 0, 0),
      ),
      snapshot(after),
    );
    expect(support.support, isNotNull);
    final plane = support.support!.frame;
    final expected = PlanarFrame.xz(origin: Vector3(3, 4, 5));
    expect(
      (plane.origin - expected.origin).dot(expected.normal),
      closeTo(-8, 1e-10),
    );
  });

  test('disk and annulus expose cap roles but do not attach arbitrary cylinder patches', () {
    for (final inputs in [
      [profileCircle('outer', 0, 0, 3)],
      [profileCircle('outer', 0, 0, 3), profileCircle('inner', 0, 0, 1)],
    ]) {
      final arrangement = profileArrangement(inputs);
      final cell = arrangement.regions.singleWhere(
        (r) => inputs.length == 1 || r.holes.isNotEmpty,
      );
      final result = adapt(arrangement, ids: [cell.id]);
      expect(result.references.map(role).toSet(), {
        'body',
        'startCap',
        'endCap',
      });
      expect(result.unavailableFaces, hasLength(inputs.length * 2));
      expect(result.ambiguousKeys, hasLength(inputs.length));
      final materialized = snapshot(result).materializeGeometry();
      expect(materialized.faces, hasLength(2));
      for (final ref in materialized.faces.values) {
        expect(
          PlanarSupportResolution.resolve(
            PlanarSupport.face(
              reference: ref,
              preferredDirection: Vector3(1, 0, 0),
            ),
            snapshot(result),
          ).support,
          isNotNull,
        );
      }
    }
  });

  test('lens and crescent caps remain distinct and stable across edits', () {
    final before = profileArrangement([
      profileCircle('a', 0, 0, 2),
      profileCircle('b', 2, 0, 2),
    ]);
    final after = profileArrangement([
      profileCircle('a', 10, 10, 3),
      profileCircle('b', 10, 13, 2.5),
    ]);
    final capKeys = <String>{};
    for (final cell in before.regions) {
      final ref = before
          .captureProfile(cell.id, sourceId: 'sketch:profiles')
          .reference!;
      final current = after
          .resolveProfile(ref, sourceId: 'sketch:profiles')
          .candidates
          .single;
      final oldOutputs = adapt(before, ids: [cell.id]);
      final newOutputs = adapt(after, ids: [current.id]);
      for (final output in oldOutputs.references.where(
        (r) => role(r) != 'wall',
      )) {
        expect(newOutputs.resolve(output).status, ReferenceStatus.resolved);
        if (role(output) == 'startCap') capKeys.add(output.key);
      }
    }
    expect(capKeys, hasLength(3));
  });

  test(
    'arc subdivision preserves caps and withdraws incomplete wall attachments',
    () {
      final vertical = profileArrangement([
        profileCircle('a', 0, 0, 2),
        profileCircle('b', 0, 2, 2),
      ]);
      final lens = vertical.regions.singleWhere(
        (r) => r.locate(Vector2(0, 1)) == RegionPointLocation.inside,
      );
      final old = adapt(vertical, ids: [lens.id]);
      final walls = old.references.where((r) => role(r) == 'wall').toList();
      expect(walls, hasLength(2));
      final horizontal = profileArrangement([
        profileCircle('a', 0, 0, 2),
        profileCircle('b', 2, 0, 2),
      ]);
      final nextLens = horizontal.regions.singleWhere(
        (r) => r.locate(Vector2(1, 0)) == RegionPointLocation.inside,
      );
      final next = adapt(horizontal, ids: [nextLens.id]);
      for (final wall in walls) {
        expect(next.resolve(wall).status, ReferenceStatus.ambiguous);
        expect(next.resolve(wall).candidateCount, 2);
        expect(next.references, isNot(contains(wall)));
        expect(snapshot(next).resolve(wall).status, ReferenceStatus.missing);
        expect(
          PlanarSupportResolution.resolve(
            PlanarSupport.face(
              reference: wall,
              preferredDirection: Vector3(1, 0, 0),
            ),
            snapshot(next),
          ).support,
          isNull,
        );
      }
      for (final ref in old.references.where((r) => role(r) != 'wall')) {
        expect(next.resolve(ref).status, ReferenceStatus.resolved);
      }
      expect(snapshot(next).materializeGeometry().faces, hasLength(2));
    },
  );

  test('unaffected component keys survive local-index reordering, split, merge and deletion', () {
    final before = profileArrangement([
      profileCircle('m', 0, 0, 1),
      ...profileRectangle('z', 10, 0, 3, 4),
    ]);
    final old = adapt(before);
    final retained = old.references.where((r) => r.key.contains('z:')).toList();
    final lost = old.references.where((r) => !r.key.contains('z:')).toList();
    expect(retained, hasLength(7));
    final variants = [
      [
        profileCircle('a', -10, 0, 1),
        profileCircle('m', 0, 0, 2),
        ...profileRectangle('z', 20, 4, 2, 5),
      ],
      [
        profileCircle('m', 0, 0, 1),
        profileLine('cut', -2, 0, 2, 0),
        ...profileRectangle('z', 20, 4, 2, 5),
      ],
      [
        profileCircle('m', 0, 0, 1),
        profileCircle('other', 0, 1, 1),
        ...profileRectangle('z', 20, 4, 2, 5),
      ],
      [...profileRectangle('z', 20, 4, 2, 5)],
    ];
    for (var i = 0; i < variants.length; i++) {
      final arrangement = profileArrangement(variants[i]);
      expect(
        arrangement.isValid,
        isTrue,
        reason:
            'variant $i: ${arrangement.diagnostics.map((d) => '${d.code}: ${d.inputIds}')}',
      );
      final next = adapt(arrangement);
      for (final ref in retained) {
        expect(next.resolve(ref).status, ReferenceStatus.resolved);
      }
      for (final ref in lost) {
        expect(
          next.resolve(ref).status,
          i == 0 ? ReferenceStatus.resolved : ReferenceStatus.missing,
        );
      }
    }
  });

  test(
    'split component retires caps and body but preserves an unchanged wall',
    () {
      final before = adapt(
        profileArrangement(profileRectangle('box', 0, 0, 4, 3)),
      );
      final arrangement = profileArrangement([
        ...profileRectangle('box', 0, 0, 4, 3),
        profileLine('cut', 2, -1, 2, 4),
      ]);
      final left = arrangement.regions.singleWhere(
        (r) => r.locate(Vector2(1, 1)) == RegionPointLocation.inside,
      );
      final next = adapt(arrangement, ids: [left.id]);
      final wall = before.references.singleWhere(
        (r) =>
            role(r) == 'wall' &&
            ((jsonDecode((jsonDecode(r.key) as List)[4] as String) as List)[1]
                    as List)
                .any((s) => (s as List)[0] == 'box:left'),
      );
      expect(next.resolve(wall).status, ReferenceStatus.resolved);
      for (final ref in before.references.where((r) => role(r) != 'wall')) {
        expect(next.resolve(ref).status, ReferenceStatus.missing);
      }
    },
  );

  test('semantic outputs are independent of input permutation', () {
    final inputs = [
      profileCircle('a', 0, 0, 2),
      profileCircle('b', 2, 0, 2),
      ...profileRectangle('z', 10, 10, 3, 4),
    ];
    final original = adapt(profileArrangement(inputs));
    for (var i = 0; i < 6; i++) {
      final next = adapt(
        profileArrangement(inputs.toList()..shuffle(math.Random(i))),
      );
      expect(next.references, original.references);
      expect(next.ambiguousKeys, original.ambiguousKeys);
    }
  });

  test(
    'ambiguous output geometry receives no body or face attachment references',
    () {
      final original = adapt(
        profileArrangement(profileRectangle('r', 0, 0, 2, 3)),
      );
      final duplicate = const ExtrusionLineageAdapter().adapt(
        featureId: producer,
        profileSourceId: 'sketch:profiles',
        extrusion: ExtrusionResult(
          volumes: [
            original.extrusion.volumes.single,
            original.extrusion.volumes.single,
          ],
        ),
      );
      expect(duplicate.outputs, isEmpty);
      expect(snapshot(duplicate).materializeGeometry().faces, isEmpty);
      for (final ref in original.references) {
        expect(duplicate.resolve(ref).status, ReferenceStatus.ambiguous);
        expect(duplicate.resolve(ref).candidateCount, 2);
        expect(
          duplicate
              .resolve(
                OutputReference(
                  featureId: producer,
                  key: ref.key,
                  kind: ref.kind == OutputKind.body
                      ? OutputKind.face
                      : OutputKind.body,
                ),
              )
              .status,
          ReferenceStatus.missing,
        );
      }
    },
  );

  test('invalid extrusion and unsupported lineage are unavailable', () {
    final arrangement = profileArrangement(profileRectangle('r', 0, 0, 2, 3));
    final old = adapt(arrangement);
    final invalid = const ExtrusionLineageAdapter().adapt(
      featureId: producer,
      profileSourceId: 'sketch:profiles',
      extrusion: const AnalyticExtrusionService().extrude(
        regions: arrangement,
        regionIds: [arrangement.regions.single.id],
        frame: PlanarFrame.xy(),
        distance: 0,
      ),
    );
    for (final ref in old.references) {
      expect(invalid.resolve(ref).status, ReferenceStatus.unavailable);
    }
    final volume = old.extrusion.volumes.single;
    final unsupported = const ExtrusionLineageAdapter().adapt(
      featureId: producer,
      profileSourceId: 'sketch:profiles',
      extrusion: ExtrusionResult(
        volumes: [
          ExtrudedVolume(
            key: volume.key,
            solid: volume.solid,
            faces: volume.faces,
            profile: PlanarRegion(
              id: volume.profile.id,
              outer: RegionLoop(
                volume.profile.outer.portions.map(
                  (p) => BoundaryPortion.line(
                    start: p.start,
                    end: p.end,
                    sources: p.sources,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    expect(unsupported.outputs, isEmpty);
    for (final ref in old.references) {
      expect(unsupported.resolve(ref).status, ReferenceStatus.unavailable);
    }
  });

  test(
    'document outputs copy topology and retain exact named face correspondence',
    () {
      final result = adapt(
        profileArrangement(profileRectangle('r', 0, 0, 2, 3)),
      );
      final geometry = snapshot(result).materializeGeometry();
      final face = geometry.faces.keys.first;
      face.outerWire.edges.first.begin.vector.x = 1000;
      expect(
        snapshot(result)
            .materializeGeometry()
            .faces
            .keys
            .first
            .outerWire
            .edges
            .first
            .begin
            .vector
            .x,
        isNot(1000),
      );
      expect(() => result.outputs.clear(), throwsUnsupportedError);
      expect(() => result.ambiguousKeys.clear(), throwsUnsupportedError);
    },
  );
}
