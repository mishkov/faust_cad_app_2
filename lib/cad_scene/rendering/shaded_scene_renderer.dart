import 'dart:math' as math;
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face_index.dart';

import 'viewport_layer_counts.dart';
import 'curved_triangle_visibility.dart';
import 'projected_mesh_batch.dart';
import 'projected_edge_visibility.dart';

import 'package:flutter/material.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_primitivies/face.dart';
import '../cad_primitivies/edge.dart';

/// Vector rendering with per-region depth comparisons for planar and tessellated CAD geometry.
///
/// Reciprocal depth is affine after perspective projection. Subtracting only
/// the closer part of each occluder handles intersecting faces and cyclic
/// overlaps that cannot be resolved by sorting whole faces or objects.
class ShadedSceneRenderer {
  ShadedSceneRenderer(
    CameraConfig camera, {
    this.layerCounts,
    this.devicePixelRatio = 1,
  }) : _projection = CameraProjection(camera);

  final ViewportLayerCounts? layerCounts;
  final double devicePixelRatio;

  final CameraProjection _projection;
  final _cameraPoints = Map<Vector3, Vector3>.identity();
  // Synchronous UI-isolate scratch. No model/camera references survive paint.
  static final _visibility = CurvedTriangleVisibility();
  static final _meshBatch = ProjectedMeshBatch();
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
  static final _hoverPaint = Paint()
    ..color = const Color(0xff00bcd4)
    ..strokeWidth = 2;
  static final _standalonePaint = Paint()
    ..color = Colors.red
    ..strokeWidth = 1;

  void paint(
    Canvas canvas,
    Size size,
    TessellatedScene scene, {
    Set<Face> selectedFaces = const {},
    Edge? selectedEdge,
    Face? hoveredFace,
  }) {
    try {
      _paintFrame(
        canvas,
        size,
        scene,
        selectedFaces: selectedFaces,
        selectedEdge: selectedEdge,
        hoveredFace: hoveredFace,
      );
    } finally {
      _cameraPoints.clear();
      _meshBatch.clear();
      _visibility.endFrame();
    }
  }

  void _paintFrame(
    Canvas canvas,
    Size size,
    TessellatedScene scene, {
    required Set<Face> selectedFaces,
    Edge? selectedEdge,
    Face? hoveredFace,
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
          face.source == hoveredFace,
        );
        if (projected != null) faces.add(projected);
      } else {
        for (final triangle in face.triangles) {
          final projected = _projectTriangle(
            triangle,
            size,
            face.source == hoveredFace,
            selectedFaces.contains(face.source),
          );
          if (projected != null) faces.add(projected);
        }
      }
    }

    // Stable compositing also makes antialiased boundary pixels independent
    // of object order when two visible surfaces meet.
    faces.sort(_compareFaces);
    final index = ProjectedFaceIndex(faces, size);
    if (layerCounts != null) {
      layerCounts!.projectionMicroseconds = timer!.elapsedMicroseconds;
    }

    Float64List? transform;
    var supportedTransform = true;
    _visibility.beginFrame();
    _meshBatch.clear();
    void flushMesh() => _meshBatch.flush(canvas, layerCounts);

    for (final face in faces) {
      final bias = !face.isMesh
          ? 0.0
          : (face.inverseDepth.x * face.bounds.center.dx +
                        face.inverseDepth.y * face.bounds.center.dy +
                        face.inverseDepth.z)
                    .abs() *
                1e-10;
      if (face.meshPoints != null) {
        if (transform == null) {
          transform = canvas.getTransform();
          supportedTransform =
              transform[1] == 0 &&
              transform[4] == 0 &&
              transform[0].isFinite &&
              transform[0] != 0 &&
              transform[5] != 0 &&
              transform[5].isFinite &&
              transform[12].isFinite &&
              transform[13].isFinite &&
              devicePixelRatio.isFinite &&
              devicePixelRatio > 0 &&
              transform[3] == 0 &&
              transform[7] == 0 &&
              transform[15] == 1;
        }

        final coverage = !supportedTransform
            ? TriangleCoverage.fallback
            : _visibility.resolve(
                face,
                index,
                bias: bias,
                pixelScaleX: transform[0] * devicePixelRatio,
                pixelScaleY: transform[5] * devicePixelRatio,
                pixelTranslateX: transform[12] * devicePixelRatio,
                pixelTranslateY: transform[13] * devicePixelRatio,
              );
        if (coverage == TriangleCoverage.hidden) {
          layerCounts?.hiddenTriangles++;
          continue;
        }
        if (coverage == TriangleCoverage.visible ||
            coverage == TriangleCoverage.partial) {
          if (coverage == TriangleCoverage.partial) {
            layerCounts?.resolvedTriangles++;
          }
          _meshBatch.addVisible(canvas, _visibility, layerCounts);
          continue;
        }
        layerCounts?.visibilityFallbacks++;
      }
      final masks = _occlusionMasks(
        face.bounds,
        face.inverseDepth,
        index,
        skip: face,
        bias: bias,
      );
      if (face.isMesh &&
          masks.isNotEmpty &&
          masks.length <= 2 &&
          _completelyErased(face.path, masks)) {
        layerCounts?.hiddenTriangles++;
        continue;
      }
      if (masks.isEmpty && face.meshPoints != null) {
        _meshBatch.addFace(canvas, face, layerCounts);
        continue;
      }
      // Every local depth comparison is complete before a cell is batched.
      // Flush at incompatible draws to retain the original compositing order.
      flushMesh();
      // Erasing requires an isolated layer; unmasked draws can use the shared
      // canvas directly without changing depth order or antialiasing.
      if (masks.isNotEmpty) {
        if (!face.isMesh) {
          layerCounts?.planarFaces++;
        } else {
          layerCounts?.curvedTriangles++;
        }
        canvas.saveLayer(face.bounds.inflate(1), _layerPaint);
      }
      try {
        if (face.isMesh) {
          final vertices =
              face.vertices ??
              ui.Vertices(
                ui.VertexMode.triangleFan,
                face.meshPoints!,
                colors: face.meshColors,
              );
          // Mesh cells share samples. Disable per-cell antialiasing to avoid
          // translucent hairlines along artificial internal boundaries.
          layerCounts?.meshDraws++;
          layerCounts?.meshVertices += face.meshPoints?.length ?? 0;
          try {
            canvas.drawVertices(vertices, BlendMode.modulate, _meshPaint);
          } finally {
            if (face.vertices == null) vertices.dispose();
          }
        } else {
          layerCounts?.planarDraws++;
          canvas.drawPath(face.path, Paint()..color = face.color);
        }
        for (final mask in masks) {
          layerCounts?.maskDraws++;
          canvas.drawPath(mask, _erasePaint);
        }
      } finally {
        if (masks.isNotEmpty) canvas.restore();
      }
    }
    flushMesh();

    if (layerCounts != null) {
      layerCounts!.facesMicroseconds =
          timer!.elapsedMicroseconds - layerCounts!.projectionMicroseconds;
    }

    // Draw outlines and standalone geometry against the same face depths.
    // This also hides grid lines and cavity edges behind opaque material.
    // Boundary strokes finish last so antialiased hole rims stay black even
    // where a standalone line emerges from behind them.
    for (final (:points, :boundary, :hovered) in [
      for (final edge in scene.shadedEdges.where((e) => !e.boundary))
        (points: edge.points, boundary: edge.boundary, hovered: false),
      for (final edge in scene.shadedEdges.where((e) => e.boundary))
        (points: edge.points, boundary: edge.boundary, hovered: false),
      for (final face in scene.faces.where((f) => f.source == hoveredFace))
        for (final loop in face.loops)
          if (loop.isNotEmpty)
            (points: [...loop, loop.first], boundary: true, hovered: true),
      for (final points in scene.selectionSamples(selectedEdge))
        (points: points, boundary: true, hovered: true),
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
        final beginDepth = _depthScore(clipped.begin.y);
        final endDepth = _depthScore(clipped.end.y);
        final gradient = (endDepth - beginDepth) / lengthSquared;
        final inverseDepth = Vector3(
          delta.dx * gradient,
          delta.dy * gradient,
          beginDepth - gradient * (delta.dx * p.dx + delta.dy * p.dy),
        );
        final bias = math.max(beginDepth.abs(), endDepth.abs()) * 1e-6;
        final bounds = Rect.fromPoints(p, q).inflate(1.5);
        final visibility = ProjectedEdgeVisibility.resolve(
          p,
          q,
          inverseDepth,
          index,
          bias: bias,
        );
        if (visibility.coverage == EdgeCoverage.hidden) {
          layerCounts?.hiddenEdges++;
          continue;
        }
        final masks = visibility.coverage == EdgeCoverage.visible
            ? const <Path>[]
            : _occlusionMasks(
                bounds,
                inverseDepth,
                index,
                // A small relative bias retains boundaries on their own surfaces.
                bias: bias,
                candidates: visibility.occluders,
              );
        // Adjacent nearer mesh cells may jointly cover the full stroke even
        // though each cell touches it. Only remove a draw when the padded
        // stroke envelope is empty after the exact existing masks.
        if (masks.isNotEmpty &&
            masks.length <= 2 &&
            masks.any((mask) => mask.contains((p + q) / 2)) &&
            _completelyErased(_strokeEnvelope(p, q), masks)) {
          layerCounts?.hiddenEdges++;
          continue;
        }
        if (masks.isNotEmpty) {
          layerCounts?.edges++;
          canvas.saveLayer(bounds, _layerPaint);
        }
        try {
          layerCounts?.edgeDraws++;
          canvas.drawLine(
            p,
            q,
            hovered
                ? _hoverPaint
                : boundary
                ? _boundaryPaint
                : _standalonePaint,
          );
          for (final mask in masks) {
            layerCounts?.maskDraws++;
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
    layerCounts?.visibilityWork = _visibility.frameWork;
    timer?.stop();
  }

  static bool _completelyErased(Path original, List<Path> masks) {
    // A bounds rejection avoids native path work for clearly visible cells.
    var coverageBounds = masks.first.getBounds();
    for (var i = 1; i < masks.length; i++) {
      coverageBounds = coverageBounds.expandToInclude(masks[i].getBounds());
    }
    final bounds = original.getBounds();
    if (bounds.left < coverageBounds.left ||
        bounds.top < coverageBounds.top ||
        bounds.right > coverageBounds.right ||
        bounds.bottom > coverageBounds.bottom) {
      return false;
    }
    var remaining = original;
    for (final mask in masks) {
      remaining = Path.combine(PathOperation.difference, remaining, mask);
      if (remaining.getBounds().isEmpty) return true;
    }
    return false;
  }

  static Path _strokeEnvelope(Offset p, Offset q) {
    final direction = (q - p) / (q - p).distance;
    final along = direction * 1.5;
    final across = Offset(-direction.dy, direction.dx) * 1.5;
    return Path()..addPolygon([
      p - along - across,
      q + along - across,
      q + along + across,
      p - along + across,
    ], true);
  }

  ProjectedFace? _projectFace(
    TessellatedFace face,
    Size size,
    bool selected,
    bool hovered,
  ) {
    final surface = face.source.surface;
    if (surface is! PlaneSurface) return null;
    final origin = _toCameraSpace(surface.origin);
    final normal = _projection.toCameraDirection(surface.normal);
    normal.normalize();
    final planeDistance = normal.dot(origin);
    // A plane through the eye projects to a line, not a fillable surface.
    if (_edgeOn(normal, planeDistance)) return null;
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
    final inverseDepth = _planeDepth(normal, planeDistance, size);
    // Faces are two-sided; choose the normal facing the camera. The light is
    // expressed in camera coordinates, so right/up stay brighter during orbit.
    if (_projection.cameraConfig.isOrthographic
        ? normal.y > 0
        : planeDistance > 0) {
      normal.negate();
    }
    final brightness = 0.32 + 0.5 * math.max(0.0, normal.dot(_light));
    final gray = (255 * brightness).round();
    return ProjectedFace(
      path,
      inverseDepth,
      _hoverColor(
        selected
            ? Color.fromARGB(255, gray ~/ 2, gray, 255)
            : Color.fromARGB(255, gray, gray, gray),
        hovered,
      ),
      contours: contours,
    );
  }

  ProjectedFace? _projectTriangle(
    RenderTriangle triangle,
    Size size,
    bool hovered,
    bool selected,
  ) {
    final camera = triangle.points.map(_toCameraSpace).toList();
    final normal = (camera[1] - camera[0]).cross(camera[2] - camera[0]);
    if (normal.length2 < 1e-24) return null;
    normal.normalize();
    final distance = normal.dot(camera[0]);
    if (_edgeOn(normal, distance)) return null;
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
      if (_projection.cameraConfig.isOrthographic ? n.y > 0 : n.dot(p) > 0) {
        n.negate();
      }
      final gray = (255 * (0.32 + 0.5 * math.max(0.0, n.dot(_light))))
          .round()
          .clamp(0, 255);
      colors.add(
        _hoverColor(
          selected
              ? Color.fromARGB(255, gray ~/ 2, gray, 255)
              : Color.fromARGB(255, gray, gray, gray),
          hovered,
        ),
      );
    }

    return ProjectedFace(
      Path()..addPolygon(points, true),
      _planeDepth(normal, distance, size),
      Colors.white,
      contours: [points],
      meshPoints: points,
      meshColors: colors,
    );
  }

  Color _hoverColor(Color color, bool hovered) =>
      hovered ? Color.lerp(color, Colors.white, 0.16)! : color;

  bool _edgeOn(Vector3 normal, double distance) =>
      (_projection.cameraConfig.isOrthographic ? normal.y : distance).abs() <
      1e-10;

  double _depthScore(double depth) => _projection.cameraConfig.isOrthographic
      ? -depth / _projection.cameraConfig.focusDistance
      : 1 / depth;

  Vector3 _planeDepth(Vector3 normal, double distance, Size size) {
    final camera = _projection.cameraConfig;
    final divisor = camera.isOrthographic ? normal.y : distance;
    final a = normal.x / (camera.focalLength * divisor);
    final b = -normal.z / (camera.focalLength * divisor);
    final c = camera.isOrthographic
        ? -distance / (normal.y * camera.focusDistance)
        : normal.y / distance;
    // Larger scores are nearer: reciprocal depth in perspective, negative
    // linear depth in a parallel view. Both are affine over screen space.
    return Vector3(a, b, c - a * size.width / 2 - b * size.height / 2);
  }

  List<Path> _occlusionMasks(
    Rect bounds,
    Vector3 inverseDepth,
    ProjectedFaceIndex index, {
    ProjectedFace? skip,
    double bias = 0,
    Iterable<ProjectedFace>? candidates,
  }) {
    final masks = <Path>[];
    for (final occluder in candidates ?? index.query(bounds)) {
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
      final whollyNearer = minDx + minDy + difference.z > minTolerance;
      final mask = whollyNearer
          ? occluder.path
          : occluder.closerRegion(difference);
      if ((whollyNearer ? occluder.bounds : mask.getBounds()).isEmpty) continue;
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
