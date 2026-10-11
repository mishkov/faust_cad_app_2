import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_context.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_failure.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/reference_resolution.dart';
import 'package:faust_cad_app_2/extrusion/extrusion.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../support/sketch_fixtures.dart';

final sketchId = FeatureId('authored-sketch');
final extrusionId = FeatureId('test-extrusion');
final attachmentId = FeatureId('attached-sketch');

// A test-only consumer proves the adapters compose with history without adding
// a production ExtrudeFeature or registering any new editor behavior.
List<FeatureOutput> evaluateExtrusion(
  FeatureDefinition definition,
  FeatureEvaluationContext context,
) {
  final sketch = context.input('sketch').data as SketchGeometry;
  final regions = const PlanarRegionEngine().build(
    const SketchPlanarAdapter().adaptSolved(sketch.solved),
  );
  final references = ProfileSelectionReference.fromJson(
    definition.parameters['profiles'] as Map<String, Object?>,
  );
  final selected = regions.resolveProfiles(
    references,
    sourceId: sketchId.value,
  );
  if (selected.status != RegionResolutionStatus.resolved) {
    throw FeatureEvaluationFailure(
      message: 'Profile ${selected.status.name}',
      diagnostics: {'profileStatus': selected.status.name},
    );
  }
  final result = const AnalyticExtrusionService().extrude(
    regions: regions,
    regionIds: selected.regions.map((r) => r.id),
    frame: sketch.frame,
    distance: (definition.parameters['distance'] as num).toDouble(),
  );
  if (!result.isValid) throw StateError('Extrusion unavailable');
  return const ExtrusionLineageAdapter()
      .adapt(
        featureId: definition.id,
        profileSourceId: sketchId.value,
        extrusion: result,
      )
      .outputs;
}

void main() {
  test('Task 10 sketch IDs, persisted selection, face attachments and undo rebuild together', () {
    final authored = rectangleSketch();
    final regions = const PlanarRegionEngine().build(
      const SketchPlanarAdapter().adapt(authored),
    );
    final selected = ProfileSelectionReference([
      regions
          .captureProfile(regions.regions.single.id, sourceId: sketchId.value)
          .reference!,
    ]);
    final document = DocumentController(
      evaluators: {
        SketchFeature.type: SketchFeature.evaluate,
        'test-extrusion': evaluateExtrusion,
      },
      features: [
        SketchFeature.definition(id: sketchId, sketch: authored),
        FeatureDefinition(
          id: extrusionId,
          type: 'test-extrusion',
          parameters: {'profiles': selected.toJson(), 'distance': 5},
          inputs: {
            'sketch': OutputReference(
              featureId: sketchId,
              key: SketchFeature.outputKey,
              kind: OutputKind.sketch,
            ),
          },
        ),
      ],
    );
    final materialized = document.evaluation.materializeGeometry();
    final body = materialized.bodies.values.single;
    // The end cap is the plane at z=5; this query identifies a fixture face only.
    final cap = materialized.faces.entries
        .singleWhere(
          (e) =>
              e.key.outerWire.edges.every((edge) => edge.begin.vector.z == 5),
        )
        .value;
    document.setFeature(
      SketchFeature.definition(
        id: attachmentId,
        sketch: rectangleSketch(
          support: PlanarSupport.face(
            reference: cap,
            preferredDirection: Vector3(1, 0, 0),
          ),
        ),
      ),
    );
    expect(
      document.evaluation.features[attachmentId]!.state,
      FeatureState.valid,
    );
    final wider = authored.copyWith(
      points: [
        for (final point in authored.points.values)
          SketchPoint(id: point.id, x: point.x * 2 + 10, y: point.y + 4),
      ],
    );
    document.updateParameters(sketchId, {
      SketchFeature.parameterKey: wider.toParameters(),
    });
    expect(document.evaluation.resolve(body).status, ReferenceStatus.resolved);
    expect(document.evaluation.resolve(cap).status, ReferenceStatus.resolved);
    expect(
      document.evaluation.features[attachmentId]!.state,
      FeatureState.valid,
    );
    document.updateParameters(extrusionId, {
      'profiles': selected.toJson(),
      'distance': 8,
    });
    expect(
      document.evaluation.features[attachmentId]!.support!.frame.origin.z,
      8,
    );
    final opened = wider.copyWith(segments: wider.segments.values.skip(1));
    document.updateParameters(sketchId, {
      SketchFeature.parameterKey: opened.toParameters(),
    });
    expect(
      document.evaluation.features[extrusionId]!.diagnostics['profileStatus'],
      'missing',
    );
    expect(
      document.evaluation.resolve(cap).status,
      ReferenceStatus.unavailable,
    );
    expect(
      document.evaluation.features[attachmentId]!.state,
      FeatureState.failed,
    );
    expect(
      document.evaluation.features[attachmentId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(document.evaluation.materializeGeometry().faces, isEmpty);
    document.undo();
    expect(document.evaluation.resolve(cap).status, ReferenceStatus.resolved);
    expect(
      document.evaluation.features[attachmentId]!.state,
      FeatureState.valid,
    );
    expect(
      document.evaluation.features[attachmentId]!.support!.frame.origin.z,
      8,
    );
    document.dispose();
  });
}
