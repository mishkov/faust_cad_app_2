import 'dart:convert';
import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../support/linked_extrusion_fixtures.dart';
import '../support/extrusion_validation.dart';

void main() {
  for (final fixture in [
    ('rectangle', rectangles(), 1, 12.0, 0),
    ('circle', circles(), 1, math.pi * 4, 0),
    ('annulus', circles(annulus: true), 1, math.pi * 8, 1),
    ('overlap union', rectangles(secondX: 2, secondY: 1), 1, 20.0, 0),
    ('edge adjacent union', rectangles(secondX: 4), 1, 24.0, 0),
    ('separate components', rectangles(secondX: 10), 2, 24.0, 0),
  ]) {
    test(
      '${fixture.$1}: linked bodies, analytic volume, holes and reverse',
      () {
        final doc = linkedDocument(
          fixture.$2,
          outerOnly: fixture.$1 == 'annulus',
        );
        addTearDown(doc.dispose);
        expect(
          doc.evaluation.features[linkedExtrusionId]!.state,
          FeatureState.valid,
        );
        final before = doc.evaluation
            .materializeGeometry()
            .bodies
            .values
            .toSet();
        for (final reverse in [false, true]) {
          doc.updateParameters(linkedExtrusionId, {'reverse': reverse});
          final geometry = doc.evaluation.materializeGeometry();
          expect(geometry.bodies.length, fixture.$3);
          expect(geometry.bodies.values.toSet(), before);
          expect(
            geometry.bodies.keys
                .cast<Solid>()
                .map((s) => analyticBoundaryVolume(s, PlanarFrame.xy()))
                .reduce((a, b) => a + b),
            closeTo(fixture.$4 * 5, 1e-7),
          );
          final cap = geometry.faces.entries
              .where((e) => jsonDecode(e.value.key)[3] == 'endCap')
              .toList();
          expect(cap.length, fixture.$3);
          for (final e in cap) {
            expect(e.key.innerWires.length, fixture.$5);
            expect(
              e.key.outerWire.edges.every(
                (edge) => edge.begin.vector.z == (reverse ? -5 : 5),
              ),
              isTrue,
            );
          }
        }
        final parameters = doc.features.last.parameters;
        expect(
          ProfileSelectionReference.fromJson(
            jsonDecode(jsonEncode(parameters['profiles']))
                as Map<String, Object?>,
          ),
          profilesOf(fixture.$2, outerOnly: fixture.$1 == 'annulus'),
        );
        expect(parameters['distance'], 5);
      },
    );
  }

  test('point-only material contact is diagnosed and publishes no bodies', () {
    final doc = linkedDocument(rectangles(secondX: 4, secondY: 3));
    addTearDown(doc.dispose);
    final result = doc.evaluation.features[linkedExtrusionId]!;
    expect(result.state, FeatureState.failed);
    expect(result.diagnostics['extrusionCode'], 'invalidSelection');
    expect(result.message, contains('point'));
    expect(doc.evaluation.geometry, isEmpty);
  });

  test('geometry, distance, reverse, undo and redo rebuild with persistent cap support', () {
    final authored = rectangles();
    final doc = linkedDocument(authored);
    addTearDown(doc.dispose);
    final attachedId = FeatureId('cap-sketch');
    final cap = doc.evaluation.materializeGeometry().faces.values.singleWhere(
      (r) => jsonDecode(r.key)[3] == 'endCap',
    );
    doc.addFeature(
      SketchFeature.definition(
        id: attachedId,
        sketch: circles().copyWith(
          support: PlanarSupport.face(
            reference: cap,
            preferredDirection: Vector3(1, 0, 0),
          ),
        ),
      ),
    );
    final body = doc.evaluation.materializeGeometry().bodies.values.single;
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: authored
          .copyWith(
            points: [
              for (final p in authored.points.values)
                SketchPoint(id: p.id, x: p.x * 2 + 10, y: p.y + 4),
            ],
          )
          .toParameters(),
    });
    expect(
      doc.evaluation.rebuiltFeatures,
      containsAll([linkedSketchId, linkedExtrusionId, attachedId]),
    );
    expect(doc.evaluation.resolve(body).status, ReferenceStatus.resolved);
    expect(doc.evaluation.resolve(cap).status, ReferenceStatus.resolved);
    doc.updateParameters(linkedExtrusionId, {'distance': 8, 'reverse': true});
    expect(doc.evaluation.features[attachedId]!.support!.frame.origin.z, -8);
    expect(doc.evaluation.features[attachedId]!.state, FeatureState.valid);
    doc.undo();
    expect(doc.evaluation.features[attachedId]!.support!.frame.origin.z, 5);
    doc.redo();
    expect(doc.evaluation.features[attachedId]!.support!.frame.origin.z, -8);
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: authored
          .copyWith(segments: authored.segments.values.skip(1))
          .toParameters(),
    });
    expect(
      doc.evaluation.features[linkedExtrusionId]!.diagnostics['profileStatus'],
      'missing',
    );
    expect(
      doc.evaluation.features[attachedId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(doc.evaluation.materializeGeometry().bodies, isEmpty);
    expect(doc.evaluation.resolve(cap).status, ReferenceStatus.unavailable);
    doc.undo();
    expect(doc.evaluation.features[attachedId]!.support!.frame.origin.z, -8);
  });

  test(
    'current constrained solve feeds extrusion and conflicting solves block it',
    () {
      final authored = circles(constrained: true);
      final doc = linkedDocument(authored);
      addTearDown(doc.dispose);
      SketchConstraint radius(double value, [String id = 'radius']) =>
          SketchConstraint(
            id: SketchConstraintId(id),
            kind: SketchConstraintKind.radius,
            references: [SketchEntityId('outer')],
            values: [value],
          );
      doc.updateParameters(linkedSketchId, {
        SketchFeature.parameterKey: authored
            .copyWith(constraints: [radius(3)])
            .toParameters(),
      });
      final solid =
          doc.evaluation.materializeGeometry().bodies.keys.single as Solid;
      expect(
        analyticBoundaryVolume(solid, PlanarFrame.xy()),
        closeTo(math.pi * 9 * 5, 1e-6),
      );
      doc.updateParameters(linkedSketchId, {
        SketchFeature.parameterKey: authored
            .copyWith(constraints: [radius(3), radius(4, 'conflict')])
            .toParameters(),
      });
      expect(
        doc.evaluation.features[linkedSketchId]!.issue,
        FeatureIssue.constraintSolveFailed,
      );
      expect(
        doc.evaluation.features[linkedExtrusionId]!.state,
        FeatureState.blocked,
      );
      expect(doc.evaluation.geometry, isEmpty);
      doc.undo();
      expect(
        doc.evaluation.features[linkedExtrusionId]!.state,
        FeatureState.valid,
      );
    },
  );

  test('upstream scene support changes move both extrusion and its cap sketch without fusing bodies', () {
    final doc = linkedDocument(rectangles(), withExtrusion: false);
    addTearDown(doc.dispose);
    final cube = FeatureId('support-cube');
    doc.addFeature(
      FeatureDefinition(
        id: cube,
        type: CubeFeature.type,
        parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 20},
      ),
    );
    final face = doc.evaluation
        .materializeGeometry()
        .faces
        .entries
        .singleWhere(
          (e) =>
              e.key.outerWire.edges.every((edge) => edge.begin.vector.z == 10),
        )
        .value;
    final supported = rectangles().copyWith(
      support: PlanarSupport.face(
        reference: face,
        preferredDirection: Vector3(1, 0, 0),
      ),
    );
    doc.setFeature(
      SketchFeature.definition(id: linkedSketchId, sketch: supported),
    );
    doc.addFeature(
      ExtrudeFeature.definition(
        id: linkedExtrusionId,
        sketch: ExtrudeFeature.sketchReference(linkedSketchId),
        profiles: profilesOf(supported),
        distance: 5,
      ),
    );
    final cap = doc.evaluation.materializeGeometry().faces.values.singleWhere(
      (r) =>
          r.featureId == linkedExtrusionId && jsonDecode(r.key)[3] == 'endCap',
    );
    final attached = FeatureId('second-sketch');
    doc.addFeature(
      SketchFeature.definition(
        id: attached,
        sketch: circles().copyWith(
          support: PlanarSupport.face(
            reference: cap,
            preferredDirection: Vector3(1, 0, 0),
          ),
        ),
      ),
    );
    expect(doc.evaluation.features[attached]!.support!.frame.origin.z, 15);
    doc.updateParameters(cube, {'z': 20});
    expect(doc.evaluation.features[attached]!.support!.frame.origin.z, 35);
    expect(
      doc.evaluation.rebuiltFeatures,
      containsAll([cube, linkedSketchId, linkedExtrusionId, attached]),
    );
    expect(doc.evaluation.materializeGeometry().bodies, hasLength(2));
    doc.updateParameters(linkedExtrusionId, {'reverse': true, 'distance': 8});
    expect(doc.evaluation.features[attached]!.support!.frame.origin.z, 22);
  });

  test('a planar wall reference follows sketch edits', () {
    final authored = rectangles();
    final doc = linkedDocument(authored);
    addTearDown(doc.dispose);
    final wall = doc.evaluation
        .materializeGeometry()
        .faces
        .entries
        .singleWhere(
          (e) =>
              jsonDecode(e.value.key)[3] == 'wall' &&
              e.key.outerWire.edges.every((edge) => edge.begin.vector.x == 4),
        )
        .value;
    expect(wall.kind, OutputKind.planarFace);
    final attached = FeatureId('wall-sketch');
    doc.addFeature(
      SketchFeature.definition(
        id: attached,
        sketch: circles().copyWith(
          support: PlanarSupport.face(
            reference: wall,
            preferredDirection: Vector3(0, 1, 0),
          ),
        ),
      ),
    );
    expect(doc.evaluation.features[attached]!.support!.frame.origin.x, 4);
    doc.updateParameters(linkedSketchId, {
      SketchFeature.parameterKey: authored
          .copyWith(
            points: [
              for (final p in authored.points.values)
                SketchPoint(id: p.id, x: p.x * 2, y: p.y),
            ],
          )
          .toParameters(),
    });
    expect(doc.evaluation.resolve(wall).status, ReferenceStatus.resolved);
    expect(doc.evaluation.features[attached]!.support!.frame.origin.x, 8);
  });

  test(
    'foreign profile producers and incorrect output references are rejected',
    () {
      final doc = linkedDocument(rectangles());
      addTearDown(doc.dispose);
      final original = doc.features.last;
      final profiles = profilesOf(rectangles());
      final foreign = ProfileSelectionReference(
        profiles.references.map(
          (r) => ProfileReference(
            sourceId: 'another-sketch/sketch',
            signature: r.signature,
          ),
        ),
      );
      expect(
        () => ExtrudeFeature.definition(
          id: linkedExtrusionId,
          sketch: ExtrudeFeature.sketchReference(linkedSketchId),
          profiles: foreign,
          distance: 5,
        ),
        throwsArgumentError,
      );
      doc.updateParameters(linkedExtrusionId, {'profiles': foreign.toJson()});
      expect(
        doc
            .evaluation
            .features[linkedExtrusionId]!
            .diagnostics['profileStatus'],
        'missing',
      );
      expect(doc.evaluation.geometry, isEmpty);
      doc.setFeature(
        FeatureDefinition(
          id: linkedExtrusionId,
          type: ExtrudeFeature.type,
          parameters: original.parameters,
          inputs: {
            ExtrudeFeature.inputKey: OutputReference(
              featureId: linkedSketchId,
              key: 'missing',
              kind: OutputKind.sketch,
            ),
          },
        ),
      );
      expect(
        doc.evaluation.features[linkedExtrusionId]!.issue,
        FeatureIssue.missingOutput,
      );
      expect(doc.evaluation.geometry, isEmpty);
    },
  );

  test('invalid parameters, broken references and failed geometry never retain current solids', () {
    final doc = linkedDocument(rectangles());
    addTearDown(doc.dispose);
    for (final values in [
      {'distance': 0},
      {'distance': -3},
      {'distance': 'bad'},
      {'reverse': 'bad'},
      {
        'profiles': {'version': 1, 'profiles': []},
      },
      {
        'profiles': {'version': 99, 'profiles': []},
      },
      {'profiles': profilesOf(circles()).toJson()},
      {'distance': 1e308},
    ]) {
      doc.updateParameters(linkedExtrusionId, values);
      expect(
        doc.evaluation.features[linkedExtrusionId]!.state,
        FeatureState.failed,
      );
      expect(doc.evaluation.materializeGeometry().bodies, isEmpty);
      doc.undo();
      expect(doc.evaluation.materializeGeometry().bodies, hasLength(1));
    }
    expect(
      () => ExtrudeFeature.definition(
        id: linkedExtrusionId,
        sketch: ExtrudeFeature.sketchReference(linkedSketchId),
        profiles: profilesOf(rectangles()),
        distance: -1,
      ),
      throwsArgumentError,
    );
    doc.removeFeature(linkedSketchId);
    expect(
      doc.evaluation.features[linkedExtrusionId]!.issue,
      FeatureIssue.missingDependency,
    );
    expect(doc.evaluation.geometry, isEmpty);
  });
}
