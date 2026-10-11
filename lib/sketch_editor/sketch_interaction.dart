enum SketchTool { select, line, circle }

enum SketchInteraction {
  idle,
  lineStart,
  lineEnd,
  circleCenter,
  circleRadius,
  dragging,
}
