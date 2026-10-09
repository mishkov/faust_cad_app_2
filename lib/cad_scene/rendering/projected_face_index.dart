import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:flutter/material.dart';

/// Bounded screen-space broad phase for face and stroke visibility queries.
class ProjectedFaceIndex {
  ProjectedFaceIndex(this.faces, this.size) {
    for (var i = 0; i < faces.length; i++) {
      for (final cell in _cells(faces[i].bounds)) {
        (buckets[cell] ??= []).add(i);
      }
    }
  }

  final List<ProjectedFace> faces;
  final Size size;
  final buckets = <int, List<int>>{};
  static const divisions = 16;

  Iterable<int> _cells(Rect bounds) sync* {
    int x(double v) =>
        (v / size.width * divisions).floor().clamp(0, divisions - 1);
    int y(double v) =>
        (v / size.height * divisions).floor().clamp(0, divisions - 1);
    for (var row = y(bounds.top); row <= y(bounds.bottom); row++) {
      for (var column = x(bounds.left); column <= x(bounds.right); column++) {
        yield row * divisions + column;
      }
    }
  }

  Iterable<ProjectedFace> query(Rect bounds) {
    final matches = <int>{};
    for (final cell in _cells(bounds)) {
      matches.addAll(buckets[cell] ?? const []);
    }
    // Keep subtraction order deterministic regardless of visited grid cells.
    final ordered = matches.toList()..sort();
    return ordered.map((i) => faces[i]);
  }
}
