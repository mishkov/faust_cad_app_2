import 'package:flutter/material.dart';

import '../sketch_editor/presentation/sketch_presentation.dart';
import '../sketch_editor/sketch_view.dart';
import 'extrusion_editor_controller.dart';

final class ExtrusionProfilePainter extends CustomPainter {
  ExtrusionProfilePainter(this.editor, this.view) : super(repaint: editor);
  final ExtrusionEditorController editor;
  final SketchView view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(const Color(0xfff6f8fa), BlendMode.src);
    for (final region in editor.regions?.regions ?? []) {
      final path = SketchPresentation.regionPath(
        region,
        (p) => view.project(p, size),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = editor.selectedRegionIds.contains(region.id)
              ? Colors.blue.withValues(alpha: 0.4)
              : Colors.blue.withValues(alpha: 0.08),
      );
    }
    final solved = editor.sketch?.solved;
    if (solved != null) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xff183c59);
      for (final line in solved.segments.values) {
        canvas.drawLine(
          view.project(solved.points[line.startPointId]!.position, size),
          view.project(solved.points[line.endPointId]!.position, size),
          stroke,
        );
      }
      for (final circle in solved.circles.values) {
        canvas.drawCircle(
          view.project(solved.points[circle.centerPointId]!.position, size),
          circle.radius * view.scale,
          stroke,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ExtrusionProfilePainter oldDelegate) =>
      oldDelegate.editor != editor || oldDelegate.view != view;
}
