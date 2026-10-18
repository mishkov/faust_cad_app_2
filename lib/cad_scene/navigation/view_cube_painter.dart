import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import 'camera_side.dart';
import 'view_cube_geometry.dart';

// Faces and their hit regions share the same projected polygons.
class ViewCubePainter extends CustomPainter {
  ViewCubePainter(
    this.geometry, {
    required this.brightness,
    this.side,
    this.highlighted = false,
    this.onSelected,
  });
  final ViewCubeGeometry geometry;
  final Brightness brightness;
  final CameraSide? side;
  final bool highlighted;
  final VoidCallback? onSelected;

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (_) => [
        if (side != null)
          CustomPainterSemantics(
            rect: geometry.path(side!).getBounds(),
            properties: SemanticsProperties(
              label: side!.label,
              button: true,
              textDirection: TextDirection.ltr,
              onTap: onSelected,
            ),
          ),
      ];

  @override
  bool hitTest(Offset position) =>
      side != null && geometry.path(side!).contains(position);

  @override
  void paint(Canvas canvas, Size size) {
    final isLight = brightness == Brightness.light;
    final face = side;
    if (face == null) {
      final origin = Vector3(-1.25, -1.25, -1.25);
      final start = geometry.project(origin);
      for (final (axis, color, label) in [
        (Vector3(3.3, 0, 0), Color(isLight ? 0xFFB43B35 : 0xFFE05B55), 'X'),
        (Vector3(0, 3.3, 0), Color(isLight ? 0xFF357D30 : 0xFF62B55B), 'Y'),
        (Vector3(0, 0, 4.2), Color(isLight ? 0xFF2769A5 : 0xFF599BDB), 'Z'),
      ]) {
        final end = geometry.project(origin + axis * 0.75);
        canvas.drawLine(
          start,
          end,
          Paint()
            ..color = color
            ..strokeWidth = 1.3,
        );
        final text = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(color: color, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final delta = end - start;
        final direction = delta.distance > 1e-6
            ? delta / delta.distance
            : const Offset(0, -1);
        final clearance =
            4 +
            (text.width * direction.dx.abs() +
                    text.height * direction.dy.abs()) /
                2;
        text.paint(
          canvas,
          end + direction * clearance - Offset(text.width / 2, text.height / 2),
        );
      }
      return;
    }
    final corners = geometry.corners(face);
    final path = geometry.path(face);
    final gray = switch (face) {
      CameraSide.top || CameraSide.bottom => isLight ? 0xFFE8E9EC : 0xFF44464A,
      CameraSide.left || CameraSide.right => isLight ? 0xFFCFD1D6 : 0xFF34363A,
      _ => isLight ? 0xFFDCDDE1 : 0xFF3C3E42,
    };
    canvas.drawPath(
      path,
      Paint()..color = highlighted ? const Color(0xFF426DE7) : Color(gray),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(isLight ? 0xFF8A8E98 : 0xFF64666C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
    // Draw text in the face plane, so it rotates with the model.
    final right = (corners[1] - corners[0]) / 2;
    final down = (corners[3] - corners[0]) / 2;
    final center = (corners[0] + corners[2]) / 2;
    final unit = geometry.scale;
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, right.dx / unit)
      ..setEntry(1, 0, right.dy / unit)
      ..setEntry(0, 1, down.dx / unit)
      ..setEntry(1, 1, down.dy / unit)
      ..setEntry(0, 3, center.dx)
      ..setEntry(1, 3, center.dy);
    final text = TextPainter(
      text: TextSpan(
        text: face.label,
        style: TextStyle(
          color: Color(isLight && !highlighted ? 0xFF31343B : 0xFFF0F0F2),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.transform(matrix.storage);
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ViewCubePainter oldDelegate) => true;
}
