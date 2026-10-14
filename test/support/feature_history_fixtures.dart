import 'dart:convert';

import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'linked_extrusion_fixtures.dart';

final branchExtrusionId = FeatureId('branch-extrusion');
final capSketchId = FeatureId('cap-sketch');
final laterExtrusionId = FeatureId('later-extrusion');
final laterSketchId = FeatureId('later-sketch');
final independentId = FeatureId('independent');

final historyEvaluators = {
  CubeFeature.type: CubeFeature.evaluate,
  SketchFeature.type: SketchFeature.evaluate,
  ExtrudeFeature.type: ExtrudeFeature.evaluate,
};

DocumentController historyDocument() {
  final setup = linkedDocument(rectangles());
  setup.addFeature(
    ExtrudeFeature.definition(
      id: branchExtrusionId,
      sketch: ExtrudeFeature.sketchReference(linkedSketchId),
      profiles: profilesOf(rectangles()),
      distance: 3,
      reverse: true,
    ),
  );
  void attach(FeatureId sketchId, FeatureId extrusionId) {
    final cap = setup.evaluation.materializeGeometry().faces.values.singleWhere(
      (ref) =>
          ref.featureId == extrusionId && jsonDecode(ref.key)[3] == 'endCap',
    );
    setup.addFeature(
      SketchFeature.definition(
        id: sketchId,
        sketch: circles().copyWith(
          support: PlanarSupport.face(
            reference: cap,
            preferredDirection: Vector3(1, 0, 0),
          ),
        ),
      ),
    );
  }

  attach(capSketchId, linkedExtrusionId);
  final sketch = SketchFeature.readDefinition(setup.features.last);
  final regions = regionsOf(sketch);
  setup.addFeature(
    ExtrudeFeature.definition(
      id: laterExtrusionId,
      sketch: ExtrudeFeature.sketchReference(capSketchId),
      profiles: ProfileSelectionReference([
        regions
            .captureProfile(
              regions.regions.single.id,
              sourceId: ExtrudeFeature.sourceId(
                ExtrudeFeature.sketchReference(capSketchId),
              ),
            )
            .reference!,
      ]),
      distance: 2,
    ),
  );
  attach(laterSketchId, laterExtrusionId);
  setup.addFeature(
    FeatureDefinition(
      id: independentId,
      type: CubeFeature.type,
      name: 'Independent cube',
      parameters: {'size': 2, 'x': 30, 'y': 0, 'z': 0},
    ),
  );
  setup.renameFeature(linkedSketchId, 'Base profile');
  setup.renameFeature(linkedExtrusionId, 'Main extrusion');
  setup.renameFeature(branchExtrusionId, 'Reverse branch');
  setup.renameFeature(capSketchId, 'Cap profile');
  setup.renameFeature(laterExtrusionId, 'Cap extrusion');
  setup.renameFeature(laterSketchId, 'Top profile');
  final document = DocumentController(
    evaluators: historyEvaluators,
    features: setup.features,
  );
  setup.dispose();
  return document;
}
