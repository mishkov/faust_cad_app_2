import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A trimmed face and its affine reciprocal depth in viewport coordinates.
class ProjectedFace {
  ProjectedFace(this.path, this.inverseDepth, this.color, {this.vertices})
    : bounds = path.getBounds();

  final Path path;
  final Rect bounds;
  final ui.Vertices? vertices;

  /// At screen (x, y), reciprocal camera depth is ax + by + c.
  final Vector3 inverseDepth;
  final Color color;
}
