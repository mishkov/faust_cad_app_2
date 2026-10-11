import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/constraint_fixtures.dart';

final sketchId = FeatureId('sketch');
final consumerId = FeatureId('consumer');
final reference = OutputReference(
  featureId: sketchId,
  key: SketchFeature.outputKey,
  kind: OutputKind.sketch,
);

DocumentController controllerFor(SketchDefinition definition) =>
    DocumentController(
      evaluators: {
        SketchFeature.type: SketchFeature.evaluate,
        CubeFeature.type: CubeFeature.evaluate,
        'consumer': (feature, context) {
          final data = context.input('profile').data as SketchGeometry;
          final regions = const PlanarRegionEngine().build(
            const SketchPlanarAdapter().adaptSolved(data.solved),
          );
          if (!regions.isValid) throw StateError('Invalid planar input');
          return [
            FeatureOutput.data(
              key: 'measurement',
              data: {
                'radius': data.solved.circles.isEmpty
                    ? null
                    : data.solved.circles.values.first.radius,
                'area': regions.regions.fold(0.0, (sum, r) => sum + r.area),
                'x': data.solved.points.values.last.x,
                'y': data.solved.points.values.last.y,
              },
            ),
          ];
        },
      },
      features: [
        SketchFeature.definition(id: sketchId, sketch: definition),
        FeatureDefinition(
          id: consumerId,
          type: 'consumer',
          inputs: {'profile': reference},
        ),
        FeatureDefinition(
          id: FeatureId('body'),
          type: CubeFeature.type,
          parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 2},
        ),
      ],
    );
SketchGeometry data(DocumentController controller) =>
    controller.evaluation.resolve(reference).output!.data as SketchGeometry;

void main() {
  test('underconstrained solved geometry feeds descendants separately from authored values', () {
    final authored = sketch(
      points: [p('o', 2, 4)],
      circles: [circle('circle', 'o', 1)],
      constraints: [
        c('radius', SketchConstraintKind.radius, ['circle'], [3]),
      ],
    );
    final controller = controllerFor(authored);
    addTearDown(controller.dispose);
    expect(controller.evaluation.features[sketchId]!.state, FeatureState.valid);
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.valid,
    );
    expect(
      data(controller).solution.status,
      SketchSolveStatus.underconstrained,
    );
    expect(data(controller).solution.degreesOfFreedom, 2);
    expect(data(controller).definition, authored);
    expect(data(controller).definition.circles.values.single.radius, 1);
    expect(
      data(controller).solved.circles.values.single.radius,
      closeTo(3, 1e-8),
    );
    final measurement =
        controller.evaluation.features[consumerId]!.outputs.single.data as Map;
    expect(measurement['radius'], closeTo(3, 1e-8));
    expect(measurement['area'], closeTo(9 * 3.141592653589793, 1e-6));
    expect(controller.evaluation.geometry, hasLength(1));
    expect(
      () => data(controller).solved.points.clear(),
      throwsUnsupportedError,
    );
  });

  test('conflicts publish structured diagnostics block descendants and preserve inspection only', () {
    final authored = sketch(
      points: [p('o', 0, 0)],
      circles: [circle('circle', 'o', 1)],
      constraints: [
        c('r1', SketchConstraintKind.radius, ['circle'], [3]),
      ],
    );
    final controller = controllerFor(authored);
    addTearDown(controller.dispose);
    final snapshot = controller.evaluation;
    final conflicted = authored.copyWith(
      constraints: [
        ...authored.constraints.values,
        c('r2', SketchConstraintKind.radius, ['circle'], [4]),
      ],
    );
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: conflicted.toParameters(),
    });
    final failed = controller.evaluation.features[sketchId]!;
    expect(failed.state, FeatureState.failed);
    expect(failed.issue, FeatureIssue.constraintSolveFailed);
    expect(failed.outputs, isEmpty);
    final diagnostics = failed.diagnostics['sketchSolve'] as Map;
    expect(diagnostics['status'], 'conflicting');
    expect(
      (diagnostics['diagnostics'] as List)
          .where((d) => (d as Map)['constraintId'] != null)
          .map((d) => (d as Map)['constraintId']),
      ['r1', 'r2'],
    );
    expect(() => diagnostics.clear(), throwsUnsupportedError);
    expect(
      failed.diagnosticOutputs.single.data,
      same(snapshot.features[sketchId]!.outputs.single.data),
    );
    expect(
      controller.evaluation.resolve(reference).status,
      ReferenceStatus.unavailable,
    );
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.blocked,
    );
    expect(controller.evaluation.features[consumerId]!.outputs, isEmpty);
    expect(
      controller.evaluation.features[consumerId]!.diagnosticOutputs,
      hasLength(1),
    );
    expect(controller.evaluation.geometry, hasLength(1));
    expect(controller.evaluation.dataOutputs, isEmpty);
    expect(snapshot.features[sketchId]!.state, FeatureState.valid);
    expect(controller.undo(), isTrue);
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.valid,
    );
    expect(controller.redo(), isTrue);
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.blocked,
    );
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: conflicted
          .copyWith(constraints: [authored.constraints.values.single])
          .toParameters(),
    });
    expect(controller.evaluation.features[sketchId]!.state, FeatureState.valid);
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.valid,
    );
    expect(controller.evaluation.features[sketchId]!.diagnostics, isEmpty);
  });

  test('numerical failure also blocks current output and recovers after a geometry edit', () {
    final authored = sketch(
      points: [p('a', 0, 0), p('b', 0, 0), p('q', 1, 1)],
      lines: [l('line', 'a', 'b')],
      constraints: [
        c('on', SketchConstraintKind.pointOnLine, ['q', 'line']),
      ],
    );
    final controller = controllerFor(authored);
    addTearDown(controller.dispose);
    final failed = controller.evaluation.features[sketchId]!;
    expect(failed.state, FeatureState.failed);
    expect(
      (failed.diagnostics['sketchSolve'] as Map)['status'],
      'numericalFailure',
    );
    expect(failed.diagnosticOutputs, isEmpty);
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.blocked,
    );
    final recovered = authored.copyWith(
      points: [p('a', 0, 0), p('b', 4, 0), p('q', 1, 1)],
    );
    controller.updateParameters(sketchId, {
      SketchFeature.parameterKey: recovered.toParameters(),
    });
    expect(
      controller.evaluation.features[consumerId]!.state,
      FeatureState.valid,
    );
    final solved = data(controller).solved;
    final direction =
        solved.points[eid('b')]!.position - solved.points[eid('a')]!.position;
    final delta =
        solved.points[eid('q')]!.position - solved.points[eid('a')]!.position;
    expect(
      (direction.x * delta.y - direction.y * delta.x).abs() / direction.length,
      lessThanOrEqualTo(1e-8),
    );
  });

  test('drag previews coalesce transaction history and preserve constraint identities', () {
    final authored = sketch(
      points: [p('a', 0, 0), p('b', 5, 0)],
      lines: [l('line', 'a', 'b')],
      constraints: [
        c('h', SketchConstraintKind.horizontal, ['line']),
        c('length', SketchConstraintKind.lineLength, ['line'], [5]),
      ],
    );
    final controller = controllerFor(authored);
    addTearDown(controller.dispose);
    controller.beginTransaction('Drag line');
    for (final target in [(8.0, 2.0), (10.0, 4.0)]) {
      final result = SketchFeature.drag(controller, sketchId, [
        SketchDragTarget(pointId: eid('b'), x: target.$1, y: target.$2),
      ]);
      expect(result.isValid, isTrue);
      at(data(controller).solved, 'b', target.$1, target.$2);
      expect(
        SketchFeature.readDefinition(controller.features.first).constraints,
        authored.constraints,
      );
      expect(controller.undoCount, 0);
    }
    expect(controller.commitTransaction(), isTrue);
    expect(controller.undoCount, 1);
    final committed = controller.features;
    expect(controller.undo(), isTrue);
    expect(SketchFeature.readDefinition(controller.features.first), authored);
    expect(controller.redo(), isTrue);
    expect(controller.features, committed);
    controller.beginTransaction('Cancelled drag');
    SketchFeature.drag(controller, sketchId, [
      SketchDragTarget(pointId: eid('b'), x: 20, y: 12),
    ]);
    controller.cancelTransaction();
    expect(controller.features, committed);
    expect(controller.undoCount, 1);
    final restored = controllerFor(
      SketchFeature.readDefinition(controller.features.first),
    );
    addTearDown(restored.dispose);
    expect(data(restored).solved.points, data(controller).solved.points);
    expect(
      data(restored).solution.toDiagnostics(),
      data(controller).solution.toDiagnostics(),
    );
  });

  test('a failed drag on an invalid sketch does not publish an edit', () {
    final authored = sketch(
      points: [p('o', 0, 0)],
      circles: [circle('circle', 'o', 1)],
      constraints: [
        c('r1', SketchConstraintKind.radius, ['circle'], [3]),
        c('r2', SketchConstraintKind.radius, ['circle'], [4]),
      ],
    );
    final controller = controllerFor(authored);
    addTearDown(controller.dispose);
    final before = controller.features;
    final result = SketchFeature.drag(controller, sketchId, [
      SketchDragTarget(pointId: eid('o'), x: 4, y: 5),
    ]);
    expect(result.isValid, isFalse);
    expect(controller.features, before);
    expect(controller.undoCount, 0);
  });
}
