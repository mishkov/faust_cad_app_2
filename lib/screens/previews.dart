import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'cad_screen.dart';

@Preview(name: 'Sketch editor and face selection', size: Size(1000, 650))
Widget viewportSelectionPreview() => const MaterialApp(home: CadScreen());

@Preview(name: 'Sketch controls at compact size', size: Size(800, 550))
Widget sketchCompactPreview() => const MaterialApp(home: CadScreen());
