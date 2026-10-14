import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/extrude_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';

final linkedSketchId = FeatureId('profile-sketch');
final linkedExtrusionId = FeatureId('extrusion');

SketchDefinition rectangles({double? secondX, double secondY = 0}) {
  final positions = [(0.0, 0.0), if (secondX != null) (secondX, secondY)];
  return SketchDefinition(
    support: const PlanarSupport.principal(PrincipalPlane.xy),
    points: [
      for (var i = 0; i < positions.length; i++)
        for (var j = 0; j < 4; j++)
          SketchPoint(
            id: SketchEntityId('p$i-$j'),
            x: positions[i].$1 + (j == 1 || j == 2 ? 4 : 0),
            y: positions[i].$2 + (j >= 2 ? 3 : 0),
          ),
    ],
    segments: [
      for (var i = 0; i < positions.length; i++)
        for (var j = 0; j < 4; j++)
          SketchLineSegment(
            id: SketchEntityId('line$i-$j'),
            startPointId: SketchEntityId('p$i-$j'),
            endPointId: SketchEntityId('p$i-${(j + 1) % 4}'),
          ),
    ],
  );
}

SketchDefinition circles({bool annulus = false, bool constrained = false}) =>
    SketchDefinition(
      support: const PlanarSupport.principal(PrincipalPlane.xy),
      points: [SketchPoint(id: SketchEntityId('center'), x: 0, y: 0)],
      circles: [
        SketchCircle(
          id: SketchEntityId('outer'),
          centerPointId: SketchEntityId('center'),
          radius: annulus ? 3 : 2,
        ),
        if (annulus)
          SketchCircle(
            id: SketchEntityId('inner'),
            centerPointId: SketchEntityId('center'),
            radius: 1,
          ),
      ],
      constraints: [
        if (constrained)
          SketchConstraint(
            id: SketchConstraintId('radius'),
            kind: SketchConstraintKind.radius,
            references: [SketchEntityId('outer')],
            values: [2],
          ),
      ],
    );

RegionResult regionsOf(SketchDefinition sketch) =>
    const PlanarRegionEngine().build(const SketchPlanarAdapter().adapt(sketch));

ProfileSelectionReference profilesOf(
  SketchDefinition sketch, {
  bool outerOnly = false,
}) {
  final regions = regionsOf(sketch);
  return ProfileSelectionReference([
    for (final r in regions.regions)
      if (!outerOnly || r.holes.isNotEmpty)
        regions
            .captureProfile(
              r.id,
              sourceId: ExtrudeFeature.sourceId(
                ExtrudeFeature.sketchReference(linkedSketchId),
              ),
            )
            .reference!,
  ]);
}

DocumentController linkedDocument(
  SketchDefinition sketch, {
  bool withExtrusion = true,
  bool outerOnly = false,
}) => DocumentController(
  evaluators: {
    SketchFeature.type: SketchFeature.evaluate,
    ExtrudeFeature.type: ExtrudeFeature.evaluate,
    CubeFeature.type: CubeFeature.evaluate,
  },
  features: [
    SketchFeature.definition(id: linkedSketchId, sketch: sketch),
    if (withExtrusion)
      ExtrudeFeature.definition(
        id: linkedExtrusionId,
        sketch: ExtrudeFeature.sketchReference(linkedSketchId),
        profiles: profilesOf(sketch, outerOnly: outerOnly),
        distance: 5,
      ),
  ],
);
