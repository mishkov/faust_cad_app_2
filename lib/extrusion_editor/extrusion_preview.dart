import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../document/document_controller.dart';
import '../document/feature_id.dart';
import '../document/features/extrude_feature.dart';
import '../document/features/sketch_feature.dart';
import '../document/planar_support.dart';
import '../sketch/sketch.dart';
import 'extrusion_editor_controller.dart';
import 'extrusion_workspace.dart';

@Preview(name: 'Linked annulus extrusion', size: Size(1100, 700))
@Preview(name: 'Linked extrusion at compact size', size: Size(800, 550))
Widget extrusionPreview() => const MaterialApp(home: _ExtrusionPreview());

class _ExtrusionPreview extends StatefulWidget {
  const _ExtrusionPreview();
  @override
  State<_ExtrusionPreview> createState() => _ExtrusionPreviewState();
}

class _ExtrusionPreviewState extends State<_ExtrusionPreview> {
  late final document = DocumentController(
    evaluators: {
      SketchFeature.type: SketchFeature.evaluate,
      ExtrudeFeature.type: ExtrudeFeature.evaluate,
    },
    features: [
      SketchFeature.definition(
        id: FeatureId('preview-sketch'),
        sketch: SketchDefinition(
          support: const PlanarSupport.principal(PrincipalPlane.xy),
          points: [SketchPoint(id: SketchEntityId('center'), x: 0, y: 0)],
          circles: [
            SketchCircle(
              id: SketchEntityId('outer'),
              centerPointId: SketchEntityId('center'),
              radius: 20,
            ),
            SketchCircle(
              id: SketchEntityId('inner'),
              centerPointId: SketchEntityId('center'),
              radius: 8,
            ),
          ],
        ),
      ),
    ],
  );
  late final editor = ExtrusionEditorController(document);

  @override
  void initState() {
    super.initState();
    editor.create(FeatureId('preview-sketch'));
    editor.toggleRegion(
      editor.regions!.regions.singleWhere((r) => r.holes.isNotEmpty).id,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) => Scaffold(
      body: editor.activeId == null
          ? Center(
              child: FilledButton(
                onPressed: () {
                  if (document.features.any(
                    (f) => f.type == ExtrudeFeature.type,
                  )) {
                    editor.open(document.features.last.id);
                  } else {
                    editor.create(FeatureId('preview-sketch'));
                  }
                },
                child: const Text('Open extrusion'),
              ),
            )
          : ExtrusionWorkspace(editor: editor),
    ),
  );

  @override
  void dispose() {
    editor.dispose();
    document.dispose();
    super.dispose();
  }
}
