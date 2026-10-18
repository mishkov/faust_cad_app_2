import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../../cad_scene/rendering/tessellation/scene_tessellator.dart';
import '../sketch_editor_controller.dart';
import '../sketch_interaction.dart';
import 'sketch_constraint_marker.dart';
import 'sketch_presentation.dart';

final class SketchPainter extends CustomPainter {
  SketchPainter(this.editor, {this.overlay = false}) : super(repaint: editor);
  final SketchEditorController editor;
  final bool overlay;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (!overlay) {
      canvas.drawColor(const Color(0xfff6f8fa), BlendMode.src);
      final view = editor.view;
      Offset project(Vector2 p) => view.project(p, size);
      final grid = Paint()
        ..color = const Color(0xffe1e7ed)
        ..strokeWidth = 1;
      final step = math
          .pow(10, (math.log(60 / view.scale) / math.ln10).floor())
          .toDouble();
      final low = view.unproject(Offset(0, size.height), size),
          high = view.unproject(Offset(size.width, 0), size);
      for (var x = (low.x / step).ceil() * step; x <= high.x; x += step) {
        canvas.drawLine(
          project(Vector2(x, low.y)),
          project(Vector2(x, high.y)),
          grid,
        );
      }
      for (var y = (low.y / step).ceil() * step; y <= high.y; y += step) {
        canvas.drawLine(
          project(Vector2(low.x, y)),
          project(Vector2(high.x, y)),
          grid,
        );
      }
      canvas.drawLine(
        project(Vector2(low.x, 0)),
        project(Vector2(high.x, 0)),
        Paint()..color = Colors.red.withValues(alpha: 0.3),
      );
      canvas.drawLine(
        project(Vector2(0, low.y)),
        project(Vector2(0, high.y)),
        Paint()..color = Colors.green.withValues(alpha: 0.3),
      );
    }
    final view = editor.view;
    Offset project(Vector2 p) => view.project(p, size);
    final boundary = overlay ? null : editor.support?.boundary;
    if (boundary != null) {
      final mesh = SceneTessellator().buildGeometry([boundary]);
      for (final face in mesh.faces) {
        for (final loop in face.loops) {
          final path = Path();
          for (var i = 0; i < loop.length; i++) {
            final p = project(editor.support!.frame.projectToLocal(loop[i]));
            if (i == 0) {
              path.moveTo(p.dx, p.dy);
            } else {
              path.lineTo(p.dx, p.dy);
            }
          }
          path.close();
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.blueGrey.withValues(alpha: 0.45),
          );
        }
      }
    }
    final presentation = editor.presentation;
    if (presentation == null) {
      canvas.restore();
      return;
    }
    for (final region in editor.regions?.regions ?? []) {
      canvas.drawPath(
        SketchPresentation.regionPath(region, project),
        Paint()
          ..color = editor.selectedRegionIds.contains(region.id)
              ? Colors.blue.withValues(alpha: 0.3)
              : Colors.blue.withValues(alpha: 0.08),
      );
    }
    Paint stroke(Object id) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = editor.selected.contains(id) ? 3 : 2
      ..color = editor.selected.contains(id)
          ? Colors.deepOrange
          : const Color(0xff183c59);
    final solved = presentation.solved;
    for (final line in solved.segments.values) {
      canvas.drawLine(
        project(solved.points[line.startPointId]!.position),
        project(solved.points[line.endPointId]!.position),
        stroke(line.id),
      );
    }
    for (final circle in solved.circles.values) {
      canvas.drawCircle(
        project(solved.points[circle.centerPointId]!.position),
        circle.radius * view.scale,
        stroke(circle.id),
      );
    }
    for (final p in solved.points.values) {
      canvas.drawCircle(
        project(p.position),
        editor.selected.contains(p.id) ? 5 : 3.5,
        Paint()
          ..color = editor.selected.contains(p.id)
              ? Colors.deepOrange
              : const Color(0xff183c59),
      );
    }
    for (final marker in SketchConstraintMarker.build(
      editor.definition!,
      solved,
      view,
      size,
    )) {
      canvas.drawRect(
        marker.bounds,
        Paint()
          ..color = editor.selectedConstraint == marker.constraint.id
              ? const Color(0xffffdfbd)
              : const Color(0xfff6f8fa),
      );
      _text(canvas, marker.label, marker.position, Colors.purple);
    }
    if (editor.anchor != null && editor.preview != null) {
      final a = project(editor.anchor!), b = project(editor.preview!.position);
      final preview = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.teal;
      if (editor.tool == SketchTool.line) {
        canvas.drawLine(a, b, preview);
      } else {
        canvas.drawCircle(a, (b - a).distance, preview);
        canvas.drawLine(a, b, preview);
      }
      _text(
        canvas,
        '${(editor.preview!.position - editor.anchor!).length.toStringAsFixed(3)} units',
        b + const Offset(14, 12),
        Colors.teal,
      );
    }
    if (editor.tool != SketchTool.select &&
        editor.preview?.label.isNotEmpty == true) {
      final p = project(editor.preview!.position);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.teal,
      );
      _text(
        canvas,
        editor.preview!.label,
        p + const Offset(14, -30),
        Colors.teal,
      );
    }
    canvas.restore();
  }

  static void _text(Canvas canvas, String text, Offset at, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 12, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(SketchPainter oldDelegate) =>
      oldDelegate.editor != editor || oldDelegate.overlay != overlay;
}
