import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'curved_triangle_visibility.dart';
import 'projected_face.dart';
import 'viewport_layer_counts.dart';

/// Fixed numerical submission storage; native vertices copy the active views.
class ProjectedMeshBatch {
  static const maxVertices = 4095;
  final _positions = Float32List(maxVertices * 2);
  final _colors = Int32List(maxVertices);
  var _count = 0;
  static final _paint = Paint()
    ..color = Colors.white
    ..isAntiAlias = false;

  void clear() => _count = 0;

  void addFace(Canvas canvas, ProjectedFace face, ViewportLayerCounts? counts) {
    final points = face.meshPoints!, colors = face.meshColors!;
    for (var i = 1; i < points.length - 1; i++) {
      _reserve(canvas, counts);
      _add(points[0].dx, points[0].dy, colors[0].toARGB32());
      _add(points[i].dx, points[i].dy, colors[i].toARGB32());
      _add(points[i + 1].dx, points[i + 1].dy, colors[i + 1].toARGB32());
    }
  }

  void addVisible(
    Canvas canvas,
    CurvedTriangleVisibility visibility,
    ViewportLayerCounts? counts,
  ) {
    for (var fragment = 0; fragment < visibility.fragmentCount; fragment++) {
      for (var i = 1; i < visibility.vertexCount(fragment) - 1; i++) {
        _reserve(canvas, counts);
        _addVisibleVertex(visibility, fragment, 0);
        _addVisibleVertex(visibility, fragment, i);
        _addVisibleVertex(visibility, fragment, i + 1);
      }
    }
  }

  void _addVisibleVertex(
    CurvedTriangleVisibility visibility,
    int fragment,
    int vertex,
  ) {
    int channel(int c) =>
        visibility.component(fragment, vertex, c).round().clamp(0, 255);
    _add(
      visibility.component(fragment, vertex, 0),
      visibility.component(fragment, vertex, 1),
      channel(5) << 24 | channel(2) << 16 | channel(3) << 8 | channel(4),
    );
  }

  void _reserve(Canvas canvas, ViewportLayerCounts? counts) {
    if (_count + 3 > maxVertices) flush(canvas, counts);
  }

  void _add(double x, double y, int color) {
    _positions[_count * 2] = x;
    _positions[_count * 2 + 1] = y;
    _colors[_count++] = color;
  }

  void flush(Canvas canvas, ViewportLayerCounts? counts) {
    if (_count == 0) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(_positions, 0, _count * 2),
      colors: Int32List.sublistView(_colors, 0, _count),
    );
    try {
      canvas.drawVertices(vertices, BlendMode.modulate, _paint);
    } finally {
      vertices.dispose();
    }
    counts?.meshBatches++;
    counts?.meshDraws++;
    counts?.meshVertices += _count;
    _count = 0;
  }
}
