import '../../extrusion/extrusion.dart';
import '../../planar_regions/planar_regions.dart';
import '../../sketch/sketch_geometry.dart';
import '../../sketch/sketch_planar_adapter.dart';
import '../feature_definition.dart';
import '../feature_evaluation_context.dart';
import '../feature_evaluation_failure.dart';
import '../feature_id.dart';
import '../feature_output.dart';
import '../output_reference.dart';
import 'sketch_feature.dart';

final class ExtrudeFeature {
  static const type = 'extrude';
  static const inputKey = 'sketch';
  static const profilesKey = 'profiles';

  static OutputReference sketchReference(FeatureId id) => OutputReference(
    featureId: id,
    key: SketchFeature.outputKey,
    kind: OutputKind.sketch,
  );

  static String sourceId(OutputReference sketch) =>
      '${sketch.featureId.value}/${sketch.key}';

  static FeatureDefinition definition({
    required FeatureId id,
    required OutputReference sketch,
    required ProfileSelectionReference profiles,
    required double distance,
    bool reverse = false,
  }) {
    if (!distance.isFinite || distance <= 0) {
      throw ArgumentError('Extrusion distance must be finite and positive');
    }
    if (sketch.kind != OutputKind.sketch ||
        sketch.key != SketchFeature.outputKey ||
        profiles.references.any((r) => r.sourceId != sourceId(sketch))) {
      throw ArgumentError('Profiles must reference the selected sketch output');
    }
    return FeatureDefinition(
      id: id,
      type: type,
      inputs: {inputKey: sketch},
      parameters: {
        profilesKey: profiles.toJson(),
        'distance': distance,
        'reverse': reverse,
      },
    );
  }

  static List<FeatureOutput> evaluate(
    FeatureDefinition definition,
    FeatureEvaluationContext context,
  ) {
    Never fail(
      String code,
      String message, {
      Map<String, Object?> details = const {},
    }) => throw FeatureEvaluationFailure(
      message: message,
      diagnostics: {'extrusionCode': code, ...details},
    );
    final distance = definition.parameters['distance'];
    final reverse = definition.parameters['reverse'];
    if (distance is! num ||
        !distance.isFinite ||
        distance <= 0 ||
        reverse is! bool) {
      fail(
        'invalidParameters',
        'Enter a positive finite extrusion distance and a reverse option.',
      );
    }
    final reference = definition.inputs[inputKey];
    if (reference == null ||
        reference.kind != OutputKind.sketch ||
        reference.key != SketchFeature.outputKey) {
      fail(
        'invalidSketch',
        'Extrusion requires a solved SketchFeature output.',
      );
    }
    final input = context.input(inputKey);
    if (input.data is! SketchGeometry) {
      fail(
        'invalidSketch',
        'Extrusion requires a solved SketchFeature output.',
      );
    }
    final sketch = input.data as SketchGeometry;
    final regions = const PlanarRegionEngine().build(
      const SketchPlanarAdapter().adaptSolved(sketch.solved),
    );
    if (!regions.isValid) {
      fail(
        'invalidSketch',
        'Sketch regions are invalid: ${regions.diagnostics.map((d) => d.message).join('; ')}',
      );
    }
    final stored = definition.parameters[profilesKey];
    if (stored is! Map<String, Object?> ||
        (stored['profiles'] is List && (stored['profiles'] as List).isEmpty)) {
      fail('emptySelection', 'Select at least one closed sketch region.');
    }
    late final ProfileSelectionReference profiles;
    try {
      profiles = ProfileSelectionReference.fromJson(stored);
    } on FormatException catch (error) {
      fail(
        'brokenProfiles',
        'Invalid stored profile references: ${error.message}',
      );
    } on ArgumentError {
      fail('brokenProfiles', 'Profile references must belong to one sketch.');
    }
    final selected = regions.resolveProfiles(
      profiles,
      sourceId: sourceId(reference),
    );
    if (selected.status != RegionResolutionStatus.resolved) {
      final cellsResolved = selected.resolutions.every(
        (r) => r.status == RegionResolutionStatus.resolved,
      );
      if (cellsResolved) {
        final material = regions.union(
          selected.resolutions.map((r) => r.candidates.single.id),
        );
        fail(
          'invalidSelection',
          'Invalid region selection: ${material.diagnostics.map((d) => d.message).join('; ')}',
        );
      }
      fail(
        'brokenProfiles',
        'Selected profile references are ${selected.status.name}. Restore their boundaries or reselect regions.',
        details: {'profileStatus': selected.status.name},
      );
    }
    final extrusion = const AnalyticExtrusionService().extrude(
      regions: regions,
      regionIds: selected.regions.map((r) => r.id),
      frame: sketch.frame,
      distance: distance.toDouble(),
      reverse: reverse,
    );
    if (!extrusion.isValid) {
      fail(
        'extrusionFailed',
        'Extrusion failed: ${extrusion.diagnostics.map((d) => d.message).join('; ')}',
      );
    }
    final lineage = const ExtrusionLineageAdapter().adapt(
      featureId: definition.id,
      profileSourceId: sourceId(reference),
      extrusion: extrusion,
    );
    if (lineage.outputs.where((o) => o.kind == OutputKind.body).length !=
        extrusion.volumes.length) {
      fail(
        'extrusionFailed',
        'Extrusion bodies lack unique profile lineage. Reselect identifiable regions.',
      );
    }
    return lineage.outputs;
  }
}
