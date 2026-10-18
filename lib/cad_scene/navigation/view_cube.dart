import 'package:flutter/material.dart';

import '../camera_config.dart';
import 'camera_side.dart';
import 'view_cube_geometry.dart';
import 'view_cube_painter.dart';

class ViewCube extends StatefulWidget {
  const ViewCube({super.key, required this.camera, required this.onSelected});
  final CameraConfig camera;
  final ValueChanged<CameraSide> onSelected;

  @override
  State<ViewCube> createState() => _ViewCubeState();
}

class _ViewCubeState extends State<ViewCube> {
  CameraSide? _hovered;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    height: 132,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final geometry = ViewCubeGeometry(widget.camera, constraints.biggest);
        final brightness = Theme.of(context).brightness;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: ViewCubePainter(geometry, brightness: brightness),
              ),
            ),
            for (final side in geometry.visibleSides)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                hitTestBehavior: HitTestBehavior.deferToChild,
                onEnter: (_) => setState(() => _hovered = side),
                onExit: (_) => setState(() => _hovered = null),
                child: GestureDetector(
                  key: ValueKey('view-cube-${side.name}'),
                  excludeFromSemantics: true,
                  onTap: () => widget.onSelected(side),
                  child: CustomPaint(
                    painter: ViewCubePainter(
                      geometry,
                      brightness: brightness,
                      side: side,
                      highlighted: _hovered == side,
                      onSelected: () => widget.onSelected(side),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
