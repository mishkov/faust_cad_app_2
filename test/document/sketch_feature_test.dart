import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/evaluation_snapshot.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_context.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../support/attachment_fixtures.dart';
import '../support/sketch_fixtures.dart';

final sketchId = FeatureId('sketch');
final supportId = FeatureId('support');
final consumerId = FeatureId('consumer');
OutputReference sketchReference({
  String key = SketchFeature.outputKey,
  OutputKind kind = OutputKind.sketch,
}) => OutputReference(featureId: sketchId, key: key, kind: kind);
PlanarSupport attachedSupport() => PlanarSupport.face(
  reference: OutputReference(
    featureId: supportId,
    key: 'plane',
    kind: OutputKind.face,
  ),
  preferredDirection: Vector3(1, 0, 0),
);
SketchGeometry sketchData(EvaluationSnapshot snapshot) =>
    snapshot.resolve(sketchReference()).output!.data as SketchGeometry;
FeatureDefinition producer({
  double angle = 0,
  double height = 0,
  String mode = 'planar',
  bool reversed = false,
}) => FeatureDefinition(
  id: supportId,
  type: 'producer',
  parameters: {
    'angle': angle,
    'height': height,
    'mode': mode,
    'reversed': reversed,
  },
);
List<FeatureOutput> produce(FeatureDefinition d, FeatureEvaluationContext c) {
  final mode = d.parameters['mode'];
  if (mode == 'missing') return [];
  if (mode == 'failed') throw StateError('Support failed');
  final planar = rectangle(
    tiltedFrame(
      (d.parameters['angle'] as num).toDouble(),
      height: (d.parameters['height'] as num).toDouble(),
    ),
  );
  final face = mode == 'curved'
      ? Cylinder(frame: PlanarFrame.xy(), radius: 2, height: 5)
            .build()
            .single
            .shells
            .single
            .faces
            .firstWhere((f) => f.surface is CylinderSurface)
      : d.parameters['reversed'] == true
      ? planar.reversed()
      : planar;
  final output = FeatureOutput(
    key: 'plane',
    kind: OutputKind.face,
    geometry: face,
  );
  return [output, if (mode == 'ambiguous') output];
}

FeatureDefinition consumer() => FeatureDefinition(
  id: consumerId,
  type: 'consumer',
  inputs: {'profile': sketchReference()},
);
List<FeatureOutput> consume(FeatureDefinition d, FeatureEvaluationContext c) {
  final output = c.input('profile');
  expect(c.dependencyOutputs(sketchId).single, same(output));
  final sketch = output.data as SketchGeometry;
  final regions = const PlanarRegionEngine().build(
    const SketchPlanarAdapter().adapt(sketch.definition),
  );
  if (!regions.isValid) throw StateError('Invalid profile');
  final world = sketch.frame.localToWorld(
    sketch.definition.points[entityId('p1')]!.position,
  );
  return [
    FeatureOutput.data(
      key: 'measurement',
      data: {
        'area': regions
            .union(regions.regions.map((r) => r.id))
            .regions
            .fold(0.0, (sum, r) => sum + r.area),
        'point': [world.x, world.y, world.z],
      },
    ),
  ];
}

final evaluators = <String, FeatureEvaluator>{
  SketchFeature.type: SketchFeature.evaluate,
  CubeFeature.type: CubeFeature.evaluate,
  'producer': produce,
  'consumer': consume,
};
Map<String, Object?> measurement(EvaluationSnapshot snapshot) =>
    snapshot.features[consumerId]!.outputs.single.data as Map<String, Object?>;

void main() {
  test('principal supports publish independent data and never enter solid rendering', () {
    for (final plane in PrincipalPlane.values) {
      final definition = rectangleSketch(
        support: PlanarSupport.principal(plane),
      );
      final doc = CadDocument(
        evaluators: evaluators,
        features: [
          SketchFeature.definition(id: sketchId, sketch: definition),
          consumer(),
        ],
      );
      expect(sketchData(doc.evaluation).definition, definition);
      expect(sketchData(doc.evaluation).frame.normal, switch (plane) {
        PrincipalPlane.xy => Vector3(0, 0, 1),
        PrincipalPlane.xz => Vector3(0, -1, 0),
        PrincipalPlane.yz => Vector3(1, 0, 0),
      });
      expect(measurement(doc.evaluation)['area'], closeTo(12, 1e-10));
      expect(doc.evaluation.dataOutputs, hasLength(2));
      expect(doc.evaluation.geometry, isEmpty);
      final materialized = doc.evaluation.materializeGeometry();
      expect(materialized.geometry, isEmpty);
      expect(materialized.faces, isEmpty);
      expect(materialized.bodies, isEmpty);
      final rendered = SceneTessellator().buildGeometry(
        doc.evaluation.geometry,
      );
      expect(rendered.faces, isEmpty);
      expect(rendered.edges, isEmpty);
      final output = doc.evaluation.resolve(sketchReference()).output!;
      expect(() => output.geometry, throwsStateError);
      expect(() => output.materialize(), throwsStateError);
    }
  });

  test(
    'mixed body and sketch outputs preserve semantic body and face behavior',
    () {
      final cube = FeatureDefinition(
        id: supportId,
        type: CubeFeature.type,
        parameters: {'size': 4, 'x': 0, 'y': 0, 'z': 0},
      );
      final support = PlanarSupport.face(
        reference: OutputReference(
          featureId: supportId,
          key: 'top',
          kind: OutputKind.planarFace,
        ),
        preferredDirection: Vector3(1, 0, 0),
      );
      final doc = CadDocument(
        evaluators: evaluators,
        features: [
          cube,
          SketchFeature.definition(
            id: sketchId,
            sketch: rectangleSketch(support: support),
          ),
        ],
      );
      expect(doc.evaluation.geometry, hasLength(1));
      expect(doc.evaluation.dataOutputs.single.kind, OutputKind.sketch);
      final materialized = doc.evaluation.materializeGeometry();
      expect(materialized.bodies, hasLength(1));
      expect(materialized.faces, hasLength(6));
      expect(doc.evaluation.features[supportId]!.outputs, hasLength(7));
      expect(
        () => doc.evaluation.features[supportId]!.outputs.first.data,
        throwsStateError,
      );
      final rendered = SceneTessellator().buildGeometry(
        doc.evaluation.geometry,
      );
      expect(rendered.faces, hasLength(6));
      expect(rendered.edges, hasLength(24));
    },
  );

  test('translated rotated and reversed attachments rebuild placement and downstream data', () {
    final authored = rectangleSketch(support: attachedSupport());
    final doc = CadDocument(
      evaluators: evaluators,
      features: [
        consumer(),
        SketchFeature.definition(id: sketchId, sketch: authored),
        producer(height: 2),
      ],
    );
    expect(doc.features[1].dependencies, {supportId});
    expect(doc.evaluation.evaluationOrder, [supportId, sketchId, consumerId]);
    final before = doc.evaluation;
    doc.setFeature(producer(angle: 0.4, height: 12));
    final sketch = sketchData(doc.evaluation);
    expect(doc.evaluation.rebuiltFeatures, {supportId, sketchId, consumerId});
    expect(sketch.definition, authored);
    expect(sketch.frame.origin, Vector3(0, 0, 12));
    expect(
      sketch.frame.normal.distanceTo(Vector3(math.sin(0.4), 0, math.cos(0.4))),
      lessThan(1e-10),
    );
    expect(sketch.frame.localToWorld(Vector2(100, 100)).isNaN, isFalse);
    final point = (measurement(doc.evaluation)['point'] as List).cast<double>();
    expect(
      Vector3.array(point).distanceTo(sketch.frame.localToWorld(Vector2(4, 0))),
      lessThan(1e-10),
    );
    expect(sketchData(before).frame.origin, Vector3(0, 0, 2));
    expect((measurement(before)['point'] as List).last, 2);
    doc.setFeature(producer(angle: 0.4, height: 12, reversed: true));
    expect(
      sketchData(doc.evaluation).frame.normal.distanceTo(-sketch.frame.normal),
      lessThan(1e-10),
    );
    expect(sketchData(doc.evaluation).definition, authored);
  });

  test('broken supports retire current sketch outputs and block consumers until recovery', () {
    final feature = SketchFeature.definition(
      id: sketchId,
      sketch: rectangleSketch(support: attachedSupport()),
    );
    final doc = CadDocument(
      evaluators: evaluators,
      features: [producer(), feature, consumer()],
    );
    final previous = sketchData(doc.evaluation);
    for (final mode in ['missing', 'ambiguous', 'curved', 'failed']) {
      doc.setFeature(producer(mode: mode));
      final result = doc.evaluation.features[sketchId]!;
      expect(result.state, FeatureState.failed);
      expect(result.issue, FeatureIssue.brokenAttachment);
      expect(result.outputs, isEmpty);
      expect(result.support, isNull);
      expect(result.diagnosticOutputs.single.data, same(previous));
      expect(
        doc.evaluation.resolve(sketchReference()).status,
        ReferenceStatus.unavailable,
      );
      expect(doc.evaluation.features[consumerId]!.state, FeatureState.blocked);
      expect(doc.evaluation.dataOutputs, isEmpty);
    }
    doc.removeFeature(supportId);
    expect(
      doc.evaluation.features[sketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    doc.setFeature(producer());
    expect(doc.evaluation.features[sketchId]!.state, FeatureState.valid);
    expect(doc.evaluation.features[consumerId]!.state, FeatureState.valid);
    expect(doc.evaluation.features[sketchId]!.diagnosticOutputs, isEmpty);
    doc.setFeature(producer(angle: math.pi / 2));
    expect(
      doc.evaluation.features[sketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(doc.evaluation.features[sketchId]!.message, contains('axis'));
  });

  test(
    'sketch references resolve by kind and key without ambiguous fallback',
    () {
      final feature = SketchFeature.definition(
        id: sketchId,
        sketch: rectangleSketch(),
      );
      final doc = CadDocument(evaluators: evaluators, features: [feature]);
      expect(
        doc.evaluation.resolve(sketchReference()).status,
        ReferenceStatus.resolved,
      );
      expect(
        doc.evaluation.resolve(sketchReference(kind: OutputKind.body)).status,
        ReferenceStatus.missing,
      );
      expect(
        doc.evaluation.resolve(sketchReference(key: 'missing')).status,
        ReferenceStatus.missing,
      );
      final ambiguous = CadDocument(
        evaluators: {
          SketchFeature.type: (d, c) => [
            ...SketchFeature.evaluate(d, c),
            ...SketchFeature.evaluate(d, c),
          ],
          'consumer': consume,
        },
        features: [feature, consumer()],
      );
      final resolution = ambiguous.evaluation.resolve(sketchReference());
      expect(resolution.status, ReferenceStatus.ambiguous);
      expect(resolution.candidateCount, 2);
      expect(resolution.output, isNull);
      expect(
        ambiguous.evaluation.features[consumerId]!.issue,
        FeatureIssue.ambiguousOutput,
      );
      for (final kind in [
        OutputKind.body,
        OutputKind.data,
        OutputKind.sketch,
      ]) {
        expect(
          () => PlanarSupport.face(
            reference: sketchReference(kind: kind),
            preferredDirection: Vector3(1, 0, 0),
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('consumer mutations cannot change sketch outputs or old snapshots', () {
    final doc = CadDocument(
      evaluators: {
        ...evaluators,
        'mutate': (d, c) {
          final sketch = c.input('profile').data as SketchGeometry;
          sketch.definition.points[entityId('p0')]!.position.x = 500;
          sketch.frame.origin.z = 500;
          sketch.definition.support.preferredDirection?.setValues(0, 0, 1);
          final inputs = const SketchPlanarAdapter().adapt(sketch.definition);
          (inputs.first as PlanarSegment).start.y = 500;
          expect(
            () => sketch.definition.points.clear(),
            throwsUnsupportedError,
          );
          throw StateError('Consumer failed after attempting mutation');
        },
      },
      features: [
        producer(height: 2),
        SketchFeature.definition(
          id: sketchId,
          sketch: rectangleSketch(support: attachedSupport()),
        ),
        FeatureDefinition(
          id: consumerId,
          type: 'mutate',
          inputs: {'profile': sketchReference()},
        ),
      ],
    );
    expect(doc.evaluation.features[consumerId]!.state, FeatureState.failed);
    final before = doc.evaluation;
    final data = sketchData(before);
    data.frame.xAxis.y = 100;
    expect(data.definition.points[entityId('p0')]!.position, Vector2.zero());
    expect(data.frame.origin.z, 2);
    expect(data.frame.xAxis, Vector3(1, 0, 0));
    expect(data.definition.support.preferredDirection, Vector3(1, 0, 0));
    doc.setFeature(producer(height: 7));
    expect(sketchData(doc.evaluation).frame.origin.z, 7);
    expect(data.frame.origin.z, 2);
  });

  test('document parameters own complete authored state and undo redo preserve attachment and IDs', () {
    final original = rectangleSketch(circle: true, support: attachedSupport());
    final controller = DocumentController(
      evaluators: evaluators,
      features: [
        producer(height: 2),
        SketchFeature.definition(id: sketchId, sketch: original),
        consumer(),
      ],
    );
    addTearDown(controller.dispose);
    final edited = original.copyWith(
      points: original.points.values.map(
        (p) => SketchPoint(id: p.id, x: p.x * 2, y: p.y),
      ),
      circles: [],
    );
    final before = controller.evaluation;
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: edited.toParameters(),
    }, label: 'Edit sketch');
    final feature = controller.features.singleWhere((f) => f.id == sketchId);
    expect(feature.support, original.support);
    expect(feature.dependencies, {supportId});
    expect(SketchFeature.readDefinition(feature), edited);
    expect(sketchData(controller.evaluation).definition, edited);
    expect(sketchData(before).definition, original);
    expect(measurement(controller.evaluation)['area'], closeTo(24, 1e-10));
    expect(controller.undo(), isTrue);
    expect(sketchData(controller.evaluation).definition, original);
    expect(controller.redo(), isTrue);
    expect(sketchData(controller.evaluation).definition, edited);
    expect(sketchData(controller.evaluation).definition.retiredIds, {
      entityId('circle'),
    });
    final independent = CadDocument(
      evaluators: evaluators,
      features: controller.features,
    );
    expect(sketchData(independent.evaluation).definition, edited);
    controller.updateParameters(supportId, {'height': 12});
    expect(sketchData(controller.evaluation).frame.origin.z, 12);
    controller.undo();
    expect(sketchData(controller.evaluation).frame.origin.z, 2);
    controller.redo();
    expect(sketchData(controller.evaluation).frame.origin.z, 12);
    controller.removeFeature(supportId);
    expect(
      controller.evaluation.features[sketchId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    controller.undo();
    expect(sketchData(controller.evaluation).definition, edited);
    expect(sketchData(controller.evaluation).frame.origin.z, 12);
    expect(sketchData(independent.evaluation).frame.origin.z, 2);
    final rebound = edited.copyWith(
      support: const PlanarSupport.principal(PrincipalPlane.xz),
    );
    controller.setFeature(
      SketchFeature.definition(id: sketchId, sketch: rebound),
    );
    expect(
      controller.features.singleWhere((f) => f.id == sketchId).dependencies,
      isEmpty,
    );
    expect(sketchData(controller.evaluation).frame.normal, Vector3(0, -1, 0));
    controller.undo();
    expect(sketchData(controller.evaluation).definition, edited);
  });

  test(
    'invalid authored values are undoable failures with isolated diagnostics',
    () {
      final original = rectangleSketch(circle: true);
      final controller = DocumentController(
        evaluators: evaluators,
        features: [
          SketchFeature.definition(id: sketchId, sketch: original),
          consumer(),
        ],
      );
      addTearDown(controller.dispose);
      final malformed = {
        ...original.toParameters(),
        'circles': [
          {'id': 'circle', 'center': 'center', 'radius': -1},
        ],
      };
      controller.updateParameters(sketchId, {
        SketchFeature.parameterKey: malformed,
      });
      (malformed['circles'] as List).clear();
      expect(
        controller.evaluation.features[sketchId]!.issue,
        FeatureIssue.evaluationFailed,
      );
      expect(
        controller.evaluation.features[sketchId]!.diagnosticOutputs.single.data,
        isA<SketchGeometry>(),
      );
      expect(
        controller.evaluation.features[consumerId]!.state,
        FeatureState.blocked,
      );
      expect(controller.evaluation.dataOutputs, isEmpty);
      controller.undo();
      expect(sketchData(controller.evaluation).definition, original);
      controller.redo();
      expect(
        controller.evaluation.features[sketchId]!.issue,
        FeatureIssue.evaluationFailed,
      );
      final failed = controller.evaluation;
      final historyCount = controller.undoCount;
      expect(
        () => controller.updateParameters(sketchId, {'bad': double.nan}),
        throwsArgumentError,
      );
      expect(controller.evaluation, same(failed));
      expect(controller.undoCount, historyCount);
      final noSupport = CadDocument(
        evaluators: evaluators,
        features: [
          FeatureDefinition(
            id: sketchId,
            type: SketchFeature.type,
            parameters: {SketchFeature.parameterKey: original.toParameters()},
          ),
        ],
      );
      expect(
        noSupport.evaluation.features[sketchId]!.issue,
        FeatureIssue.evaluationFailed,
      );
    },
  );

  test('transaction previews commit once and cancellation restores immutable authored values', () {
    final original = rectangleSketch(circle: true);
    final controller = DocumentController(
      evaluators: evaluators,
      features: [SketchFeature.definition(id: sketchId, sketch: original)],
    );
    addTearDown(controller.dispose);
    controller.beginTransaction('Edit sketch');
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: original.copyWith(circles: []).toParameters(),
    });
    expect(sketchData(controller.evaluation).definition.circles, isEmpty);
    controller.cancelTransaction();
    expect(sketchData(controller.evaluation).definition, original);
    expect(controller.undoCount, 0);
    controller.beginTransaction('Resize sketch');
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: rectangleSketch(
        width: 5,
        circle: true,
      ).toParameters(),
    });
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: rectangleSketch(
        width: 6,
        circle: true,
      ).toParameters(),
    });
    controller.commitTransaction();
    expect(controller.undoCount, 1);
    expect(
      sketchData(controller.evaluation).definition.points[entityId('p1')]!.x,
      6,
    );
    controller.undo();
    expect(sketchData(controller.evaluation).definition, original);
    controller.redo();
    expect(
      sketchData(controller.evaluation).definition.points[entityId('p1')]!.x,
      6,
    );
  });
}
