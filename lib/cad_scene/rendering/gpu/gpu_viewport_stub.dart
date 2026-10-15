import 'package:flutter/material.dart';

import '../../cad_primitivies/face.dart';
import '../../camera_config.dart';
import '../tessellation/tessellated_scene.dart';

class GpuViewport extends StatelessWidget {
  const GpuViewport({
    super.key,
    required CameraConfig camera,
    required TessellatedScene scene,
    required Set<Face> selected,
  });
  @override
  Widget build(BuildContext context) => const Center(
    child: Text('The CAD GPU prototype requires macOS Impeller.'),
  );
}
