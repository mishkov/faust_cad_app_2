import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/camera_projection.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_face_index.dart';
import 'package:flutter/material.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_primitivies/face.dart';

/// Vector rendering with per-region depth comparisons for planar and tessellated CAD geometry.
///
/// Reciprocal depth is affine after perspective projection. Subtracting only
/// the closer part of each occluder handles intersecting faces and cyclic
/// overlaps that cannot be resolved by sorting whole faces or objects.
class ShadedSceneRenderer {
  ShadedSceneRenderer(CameraConfig camera)
    : _projection = CameraProjection(camera);

  final CameraProjection _projection;
  static final _light = Vector3(0.55, -0.65, 0.8).normalized();

  void paint(
    Canvas canvas,
    Size size,
    TessellatedScene scene, {
    Set<Face> selectedFaces = const {},
  }) {
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
    faces.sort((a, b) {
      final keysA = [
        a.bounds.left,
        a.bounds.top,
        a.bounds.right,
        a.bounds.bottom,
        ...a.inverseDepth.storage,
      ];
      final keysB = [
        b.bounds.left,
        b.bounds.top,
        b.bounds.right,
        b.bounds.bottom,
        ...b.inverseDepth.storage,
      ];
      for (var i = 0; i < keysA.length; i++) {
        final order = keysA[i].compareTo(keysB[i]);
        if (order != 0) return order;
      }
      return a.color.toARGB32().compareTo(b.color.toARGB32());
    });
    final index = ProjectedFaceIndex(faces, size);

    for (final face in faces) {
      final visible = _visibleRegion(
        face.path,
        face.inverseDepth,
        index,
        size,
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
      if (face.vertices case final vertices?) {
        canvas.save();
        // Mesh cells share samples. Disable per-cell antialiasing to avoid
        // translucent hairlines along their artificial internal boundaries.
        canvas.clipPath(visible, doAntiAlias: false);
        canvas.drawVertices(
          vertices,
          BlendMode.modulate,
          Paint()
            ..color = Colors.white
            ..isAntiAlias = false,
        );
        canvas.restore();
      } else {
        canvas.drawPath(visible, Paint()..color = face.color);
      }
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
          _projection.toCameraSpace(points[i]),
          _projection.toCameraSpace(points[i + 1]),
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
        final visible = _visibleRegion(
          Path()..addRect(Rect.fromPoints(p, q).inflate(1.5)),
          inverseDepth,
          index,
          size,
          // A small relative bias retains boundaries on their own surfaces.
          bias: math.max(1 / clipped.begin.y, 1 / clipped.end.y) * 1e-6,
        );
        canvas.save();
        canvas.clipPath(visible);
        canvas.drawLine(
          p,
          q,
          Paint()
            ..color = boundary ? Colors.black : Colors.red
            ..strokeWidth = 1,
        );
        canvas.restore();
      }
    }
  }

  ProjectedFace? _projectFace(TessellatedFace face, Size size, bool selected) {
    final surface = face.source.surface;
    if (surface is! PlaneSurface) return null;
    final origin = _projection.toCameraSpace(surface.origin);
    final normal = _projection.toCameraDirection(surface.normal);
    normal.normalize();
    final planeDistance = normal.dot(origin);
    // A plane through the eye projects to a line, not a fillable surface.
    if (planeDistance.abs() < 1e-10) return null;
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final points in face.loops) {
      final loop = _projection.clipLoop([
        for (final point in points) _projection.toCameraSpace(point),
      ], screen: size);
      if (loop.length < 3) continue;
      final first = _projection.project(loop.first, screen: size);
      path.moveTo(first.x, first.y);
      for (final point in loop.skip(1)) {
        final projected = _projection.project(point, screen: size);
        path.lineTo(projected.x, projected.y);
      }
      path.close();
    }
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
    );
  }

  ProjectedFace? _projectTriangle(RenderTriangle triangle, Size size) {
    final camera = triangle.points.map(_projection.toCameraSpace).toList();
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
      vertices: ui.Vertices(ui.VertexMode.triangleFan, points, colors: colors),
    );
  }

  Path _visibleRegion(
    Path region,
    Vector3 inverseDepth,
    ProjectedFaceIndex index,
    Size size, {
    ProjectedFace? skip,
    double bias = 0,
  }) {
    for (final occluder in index.query(region.getBounds())) {
      if (identical(occluder, skip) ||
          !region.getBounds().overlaps(occluder.bounds)) {
        continue;
      }
      final difference = occluder.inverseDepth - inverseDepth;
      difference.z -= bias;
      final closerRegion = _positiveHalfPlane(difference, size);
      final hidden = Path.combine(
        PathOperation.intersect,
        occluder.path,
        closerRegion,
      );
      region = Path.combine(PathOperation.difference, region, hidden);
    }
    return region;
  }

  /// Clip the viewport to ax + by + c > 0 (the occluder is closer).
  Path _positiveHalfPlane(Vector3 coefficients, Size size) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    double distance(Offset p) =>
        coefficients.x * p.dx + coefficients.y * p.dy + coefficients.z;
    final points = <Offset>[];
    var previous = corners.last;
    var previousDistance = distance(previous);
    for (final point in corners) {
      final d = distance(point);
      if ((d > 0) != (previousDistance > 0)) {
        points.add(
          previous +
              (point - previous) * (previousDistance / (previousDistance - d)),
        );
      }
      if (d > 0) points.add(point);
      previous = point;
      previousDistance = d;
    }
    return Path()..addPolygon(points, true);
  }
}
