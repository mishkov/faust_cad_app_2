import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../document/document_controller.dart';
import '../document/feature_definition.dart';
import '../document/feature_id.dart';
import '../document/features/cube_feature.dart';
import '../document/features/extrude_feature.dart';
import '../document/features/sketch_feature.dart';
import '../document/planar_support.dart';
import '../planar_regions/planar_regions.dart';
import '../screens/cad_screen.dart';
import '../sketch/sketch.dart';

@Preview(name: 'Feature history and linked edits', size: Size(1100, 750))
@Preview(name: 'Feature history at compact size', size: Size(800, 550))
Widget featureHistoryPreview() => const MaterialApp(home: _HistoryPreview());

// The widget/state pair share the preview document's lifecycle.
class _HistoryPreview extends StatefulWidget {
  const _HistoryPreview();
  @override
  State<_HistoryPreview> createState() => _HistoryPreviewState();
}

class _HistoryPreviewState extends State<_HistoryPreview> {
  final sketchId = FeatureId('base-profile');
  final extrusionId = FeatureId('boss');
  late final sketch = SketchDefinition(
    support: const PlanarSupport.principal(PrincipalPlane.xy),
    points: [SketchPoint(id: SketchEntityId('center'), x: 15, y: 15)],
    circles: [
      SketchCircle(
        id: SketchEntityId('circle'),
        centerPointId: SketchEntityId('center'),
        radius: 12,
      ),
    ],
  );
  late final document = DocumentController(
    evaluators: {
      SketchFeature.type: SketchFeature.evaluate,
      ExtrudeFeature.type: ExtrudeFeature.evaluate,
      CubeFeature.type: CubeFeature.evaluate,
    },
    features: [SketchFeature.definition(id: sketchId, sketch: sketch)],
  );

  @override
  void initState() {
    super.initState();
    final regions = const PlanarRegionEngine().build(
      const SketchPlanarAdapter().adapt(sketch),
    );
    document.addFeature(
      ExtrudeFeature.definition(
        id: extrusionId,
        sketch: ExtrudeFeature.sketchReference(sketchId),
        profiles: ProfileSelectionReference([
          regions
              .captureProfile(
                regions.regions.single.id,
                sourceId: ExtrudeFeature.sourceId(
                  ExtrudeFeature.sketchReference(sketchId),
                ),
              )
              .reference!,
        ]),
        distance: 15,
      ),
    );
    final cap = document.evaluation
        .materializeGeometry()
        .faces
        .values
        .singleWhere((ref) => jsonDecode(ref.key)[3] == 'endCap');
    document.addFeature(
      SketchFeature.definition(
        id: FeatureId('cap-profile'),
        sketch: sketch.copyWith(
          support: PlanarSupport.face(
            reference: cap,
            preferredDirection: Vector3(1, 0, 0),
          ),
        ),
      ),
    );
    document.addFeature(
      FeatureDefinition(
        id: FeatureId('cube'),
        type: CubeFeature.type,
        name: 'Independent cube',
        parameters: {'size': 10, 'x': 40, 'y': 20, 'z': 5},
      ),
    );
    document.renameFeature(sketchId, 'Base profile');
    document.renameFeature(extrusionId, 'Boss');
    document.renameFeature(FeatureId('cap-profile'), 'Cap profile');
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () => document.updateParameters(sketchId, {
          SketchFeature.parameterKey: sketch
              .copyWith(circles: [])
              .toParameters(),
        }, label: 'Remove profile boundary'),
        child: const Text(
          'Remove base boundary to inspect failures; Undo restores it',
        ),
      ),
      Expanded(child: CadScreen(controller: document)),
    ],
  );

  @override
  void dispose() {
    document.dispose();
    super.dispose();
  }
}
