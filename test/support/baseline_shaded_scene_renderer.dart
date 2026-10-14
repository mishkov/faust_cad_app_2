// Rendering reference from PR #32 (e7af918), with optional layer counters.
// Keep this frozen so visual and native profile comparisons remain reproducible.
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';

import 'baseline_projected_face_index.dart';

import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:flutter/material.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';

/// Vector rendering with per-region depth comparisons for planar and tessellated CAD geometry.
///
/// Reciprocal depth is affine after perspective projection. Subtracting only
/// the closer part of each occluder handles intersecting faces and cyclic
/// overlaps that cannot be resolved by sorting whole faces or objects.
class BaselineShadedSceneRenderer {
  BaselineShadedSceneRenderer(CameraConfig camera, {this.layerCounts})
    : _projection = CameraProjection(camera);

  final ViewportLayerCounts? layerCounts;

  final CameraProjection _projection;
  final _cameraPoints = Map<Vector3, Vector3>.identity();
  static final _light = Vector3(0.55, -0.65, 0.8).normalized();
  static const _depthBoundsRelativeTolerance = 1e-6;
  static final _layerPaint = Paint();
  static final _meshPaint = Paint()
    ..color = Colors.white
    ..isAntiAlias = false;
  static final _erasePaint = Paint()
    ..blendMode = BlendMode.dstOut
    ..isAntiAlias = false;
  static final _boundaryPaint = Paint()
    ..color = Colors.black
    ..strokeWidth = 1;
  static final _standalonePaint = Paint()
    ..color = Colors.red
    ..strokeWidth = 1;

  void paint(
    Canvas canvas,
    Size size,
    TessellatedScene scene, {
    Set<Face> selectedFaces = const {},
  }) {
    // Shared mesh and edge samples are transformed once per paint. Clear the
    // cache between frames because model coordinates can be mutable.
    final timer = layerCounts == null ? null : (Stopwatch()..start());
    _cameraPoints.clear();
    final faces = <ProjectedFace>[];
    for (final face in scene.faces) {
      if (face.source.surface is PlaneSurface) {
        final projected = _projectFace(
          face,
          size,
          selectedFaces.contains(face.source),
        );
        if (projected != null) faces.add(projected);
      } else {
        for (final triangle in face.triangles) {
          final projected = _projectTriangle(triangle, size);
          if (projected != null) faces.add(projected);
        }
      }
    }

    // Stable compositing also makes antialiased boundary pixels independent
    // of object order when two visible surfaces meet.
    faces.sort(_compareFaces);
    final index = BaselineProjectedFaceIndex(faces, size);
    if (layerCounts != null) {
      layerCounts!.projectionMicroseconds = timer!.elapsedMicroseconds;
    }

    for (final face in faces) {
      final masks = _occlusionMasks(
        face.bounds,
        face.inverseDepth,
        index,
        skip: face,
        bias: face.vertices == null
            ? 0
            : face.inverseDepth
                      .dot(
                        Vector3(
                          face.bounds.center.dx,
                          face.bounds.center.dy,
                          1,
                        ),
                      )
                      .abs() *
                  1e-10,
      );
      // Erasing requires an isolated layer; unmasked draws can use the shared
      // canvas directly without changing depth order or antialiasing.
      if (masks.isNotEmpty) {
        if (face.vertices == null) {
          layerCounts?.planarFaces++;
        } else {
          layerCounts?.curvedTriangles++;
        }
        canvas.saveLayer(face.bounds.inflate(1), _layerPaint);
      }
      try {
        if (face.vertices case final vertices?) {
          // Mesh cells share samples. Disable per-cell antialiasing to avoid
          // translucent hairlines along artificial internal boundaries.
          canvas.drawVertices(vertices, BlendMode.modulate, _meshPaint);
        } else {
          canvas.drawPath(face.path, Paint()..color = face.color);
        }
        for (final mask in masks) {
          canvas.drawPath(mask, _erasePaint);
        }
      } finally {
        if (masks.isNotEmpty) canvas.restore();
      }
    }

    if (layerCounts != null) {
      layerCounts!.facesMicroseconds =
          timer!.elapsedMicroseconds - layerCounts!.projectionMicroseconds;
    }

    // Draw outlines and standalone geometry against the same face depths.
    // This also hides grid lines and cavity edges behind opaque material.
    // Boundary strokes finish last so antialiased hole rims stay black even
    // where a standalone line emerges from behind them.
    for (final (:points, :boundary) in [
      ...scene.shadedEdges.where((entry) => !entry.boundary),
      ...scene.shadedEdges.where((entry) => entry.boundary),
    ]) {
      for (var i = 0; i < points.length - 1; i++) {
        final clipped = _projection.clipLine(
          _toCameraSpace(points[i]),
          _toCameraSpace(points[i + 1]),
          screen: size,
        );
        if (clipped == null) continue;
        final begin = _projection.project(clipped.begin, screen: size);
        final end = _projection.project(clipped.end, screen: size);
        final p = Offset(begin.x, begin.y);
        final q = Offset(end.x, end.y);
        final delta = q - p;
        final lengthSquared = delta.distanceSquared;
        if (lengthSquared < 1e-12) continue;
        final gradient =
            (1 / clipped.end.y - 1 / clipped.begin.y) / lengthSquared;
        final inverseDepth = Vector3(
          delta.dx * gradient,
          delta.dy * gradient,
          1 / clipped.begin.y - gradient * (delta.dx * p.dx + delta.dy * p.dy),
        );
        final bounds = Rect.fromPoints(p, q).inflate(1.5);
        final masks = _occlusionMasks(
          bounds,
          inverseDepth,
          index,
          // A small relative bias retains boundaries on their own surfaces.
          bias: math.max(1 / clipped.begin.y, 1 / clipped.end.y) * 1e-6,
        );
        if (masks.isNotEmpty) {
          layerCounts?.edges++;
          canvas.saveLayer(bounds, _layerPaint);
        }
        try {
          canvas.drawLine(p, q, boundary ? _boundaryPaint : _standalonePaint);
          for (final mask in masks) {
            canvas.drawPath(mask, _erasePaint);
          }
        } finally {
          if (masks.isNotEmpty) canvas.restore();
        }
      }
    }
    if (layerCounts != null) {
      layerCounts!.edgesMicroseconds =
          timer!.elapsedMicroseconds -
          layerCounts!.projectionMicroseconds -
          layerCounts!.facesMicroseconds;
    }
    timer?.stop();
  }

  ProjectedFace? _projectFace(TessellatedFace face, Size size, bool selected) {
    final surface = face.source.surface;
    if (surface is! PlaneSurface) return null;
    final origin = _toCameraSpace(surface.origin);
    final normal = _projection.toCameraDirection(surface.normal);
    normal.normalize();
    final planeDistance = normal.dot(origin);
    // A plane through the eye projects to a line, not a fillable surface.
    if (planeDistance.abs() < 1e-10) return null;
    final path = Path()..fillType = PathFillType.evenOdd;
    final contours = <List<Offset>>[];
    for (final points in face.loops) {
      final loop = _projection.clipLoop([
        for (final point in points) _toCameraSpace(point),
      ], screen: size);
      if (loop.length < 3) continue;
      final contour = <Offset>[];
      for (final p in loop) {
        final projected = _projection.project(p, screen: size);
        contour.add(Offset(projected.x, projected.y));
      }
      contours.add(contour);
      path.addPolygon(contour, true);
    }
    if (contours.isEmpty || path.getBounds().isEmpty) return null;
    final focalLength = _projection.cameraConfig.focalLength;
    final a = normal.x / (focalLength * planeDistance);
    final b = -normal.z / (focalLength * planeDistance);
    final inverseDepth = Vector3(
      a,
      b,
      normal.y / planeDistance - a * size.width / 2 - b * size.height / 2,
    );
    // Faces are two-sided; choose the normal facing the camera. The light is
    // expressed in camera coordinates, so right/up stay brighter during orbit.
    if (planeDistance > 0) normal.negate();
    final brightness = 0.32 + 0.5 * math.max(0.0, normal.dot(_light));
    final gray = (255 * brightness).round();
    return ProjectedFace(
      path,
      inverseDepth,
      selected
          ? Color.fromARGB(255, gray ~/ 2, gray, 255)
          : Color.fromARGB(255, gray, gray, gray),
      contours: contours,
    );
  }

  ProjectedFace? _projectTriangle(RenderTriangle triangle, Size size) {
    final camera = triangle.points.map(_toCameraSpace).toList();
    final normal = (camera[1] - camera[0]).cross(camera[2] - camera[0]);
    if (normal.length2 < 1e-24) return null;
    normal.normalize();
    final distance = normal.dot(camera[0]);
    if (distance.abs() < 1e-10) return null;
    final clipped = _projection.clipLoop(camera, screen: size);
    if (clipped.length < 3) return null;
    final points = <Offset>[];
    final colors = <Color>[];
    final u = camera[1] - camera[0], v = camera[2] - camera[0];
    final uu = u.dot(u), uv = u.dot(v), vv = v.dot(v);
    final divisor = uu * vv - uv * uv;
    if (divisor <= 0) return null;
    final normals = triangle.normals
        .map(_projection.toCameraDirection)
        .toList();
    for (final p in clipped) {
      final projected = _projection.project(p, screen: size);
      points.add(Offset(projected.x, projected.y));
      final delta = p - camera[0];
      final b = (vv * delta.dot(u) - uv * delta.dot(v)) / divisor;
      final c = (uu * delta.dot(v) - uv * delta.dot(u)) / divisor;
      // Interpolate analytic oriented radial normals, including clipped points.
      final n = (normals[0] * (1 - b - c) + normals[1] * b + normals[2] * c)
          .normalized();
      if (n.dot(p) > 0) n.negate();
      final gray = (255 * (0.32 + 0.5 * math.max(0.0, n.dot(_light))))
          .round()
          .clamp(0, 255);
      colors.add(Color.fromARGB(255, gray, gray, gray));
    }
    final a = normal.x / (_projection.cameraConfig.focalLength * distance);
    final b = -normal.z / (_projection.cameraConfig.focalLength * distance);
    return ProjectedFace(
      Path()..addPolygon(points, true),
      Vector3(
        a,
        b,
        normal.y / distance - a * size.width / 2 - b * size.height / 2,
      ),
      Colors.white,
      contours: [points],
      vertices: ui.Vertices(ui.VertexMode.triangleFan, points, colors: colors),
    );
  }

  List<Path> _occlusionMasks(
    Rect bounds,
    Vector3 inverseDepth,
    BaselineProjectedFaceIndex index, {
    ProjectedFace? skip,
    double bias = 0,
  }) {
    final masks = <Path>[];
    for (final occluder in index.query(bounds)) {
      if (identical(occluder, skip) || !bounds.overlaps(occluder.bounds)) {
        continue;
      }
      final difference = occluder.inverseDepth - inverseDepth;
      difference.z -= bias;
      // An affine depth difference reaches its maximum at a bounds corner.
      // Native path bounds have float precision, so include their rounding
      // error. Touching or crossing surfaces still use contour clipping.
      final x = difference.x >= 0
          ? occluder.bounds.right
          : occluder.bounds.left;
      final y = difference.y >= 0
          ? occluder.bounds.bottom
          : occluder.bounds.top;
      final dx = difference.x * x, dy = difference.y * y;
      final tolerance =
          (dx.abs() + dy.abs() + difference.z.abs()) *
          _depthBoundsRelativeTolerance;
      if (dx + dy + difference.z < -tolerance) continue;
      final minX = difference.x >= 0
          ? occluder.bounds.left
          : occluder.bounds.right;
      final minY = difference.y >= 0
          ? occluder.bounds.top
          : occluder.bounds.bottom;
      final minDx = difference.x * minX, minDy = difference.y * minY;
      final minTolerance =
          (minDx.abs() + minDy.abs() + difference.z.abs()) *
          _depthBoundsRelativeTolerance;
      // Wholly nearer contours need no clipping. Reuse their projected path;
      // holes retain the face's even-odd fill and mesh cells remain triangles.
      final mask = minDx + minDy + difference.z > minTolerance
          ? occluder.path
          : occluder.closerRegion(difference);
      if (mask.getBounds().isEmpty) continue;
      // Each erase removes coverage from this layer only. Overlaps naturally
      // form a union without native path booleans or a growing clip stack.
      masks.add(mask);
    }
    return masks;
  }

  Vector3 _toCameraSpace(Vector3 point) =>
      _cameraPoints.putIfAbsent(point, () => _projection.toCameraSpace(point));

  static int _compareFaces(ProjectedFace a, ProjectedFace b) {
    var order = a.bounds.left.compareTo(b.bounds.left);
    if (order != 0) return order;
    order = a.bounds.top.compareTo(b.bounds.top);
    if (order != 0) return order;
    order = a.bounds.right.compareTo(b.bounds.right);
    if (order != 0) return order;
    order = a.bounds.bottom.compareTo(b.bounds.bottom);
    if (order != 0) return order;
    for (var i = 0; i < 3; i++) {
      order = a.inverseDepth[i].compareTo(b.inverseDepth[i]);
      if (order != 0) return order;
    }
    return a.color.toARGB32().compareTo(b.color.toARGB32());
  }
}
