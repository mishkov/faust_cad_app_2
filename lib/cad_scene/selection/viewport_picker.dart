import 'package:flutter/rendering.dart' show Offset, Size;
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../document/evaluated_geometry.dart';
import '../cad_primitivies/cad_primitive.dart';
import '../cad_primitivies/face.dart';
import '../cad_primitivies/edge.dart';
import '../cad_primitivies/shell.dart';
import '../cad_primitivies/solid.dart';
import '../cad_surfaces/plane_surface.dart';
import '../camera_config.dart';
import '../rendering/camera_projection.dart';
import '../rendering/tessellation/scene_tessellator.dart';
import '../rendering/tessellation/tessellated_scene.dart';
import '../rendering/tessellation/tessellation_settings.dart';
import 'viewport_hit.dart';

// Uses the exact renderer mesh. Curved faces occlude even in planar-face mode.
// Body membership and output correspondence use analytic identities, never
// triangle indices or geometric nearest-face inference.
final class ViewportPicker {
  ViewportPicker({
    required this.evaluated,
    List<CadPrimitive> extraGeometry = const [],
    SceneTessellator? tessellator,
    TessellationSettings? settings,
    Object? geometryRevision,
  }) {
    final geometry = [...evaluated.geometry, ...extraGeometry];
    scene = (tessellator ?? SceneTessellator()).buildGeometry(
      geometry,
      settings: settings,
      geometryRevision: geometryRevision,
      preserveSourceIdentity: true,
    );
    void collect(CadPrimitive primitive, CadPrimitive owner) {
      switch (primitive) {
        case Solid(:final shells):
          for (final shell in shells) {
            collect(shell, owner);
          }
        case Shell(:final faces):
          for (final face in faces) {
            collect(face, owner);
          }
        case Face():
          _owners[primitive] = owner;
      }
    }

    for (final primitive in geometry) {
      collect(primitive, primitive);
    }
    for (final face in scene.faces) {
      for (final wire in [face.source.outerWire, ...face.source.innerWires]) {
        for (final edge in wire.edges) {
          if (scene.edgeSamples.containsKey(edge)) {
            _edgeFaces[edge] = face.source;
          }
        }
      }
    }
  }

  final EvaluatedGeometry evaluated;
  late final TessellatedScene scene;
  final _owners = <Face, CadPrimitive>{};
  final _edgeFaces = <Edge, Face>{};

  ViewportHit? pick({
    required CameraConfig camera,
    required Size viewport,
    required Offset position,
    ViewportSelectionMode mode = ViewportSelectionMode.planarFace,
  }) {
    if (viewport.isEmpty ||
        !position.dx.isFinite ||
        !position.dy.isFinite ||
        position.dx < 0 ||
        position.dy < 0 ||
        position.dx > viewport.width ||
        position.dy > viewport.height) {
      return null;
    }
    if (mode == ViewportSelectionMode.inspect) {
      final edge = _pickEdge(camera, viewport, position);
      if (edge != null) return edge;
    }
    final projection = CameraProjection(camera);
    final direction = Vector3(
      (position.dx - viewport.width / 2) / camera.focalLength,
      1,
      (viewport.height / 2 - position.dy) / camera.focalLength,
    );
    final origin = camera.isOrthographic
        ? Vector3(
            direction.x * camera.focusDistance,
            0,
            direction.z * camera.focusDistance,
          )
        : Vector3.zero();
    if (camera.isOrthographic) direction.setValues(0, 1, 0);
    double? nearest;
    Face? source;
    for (final face in scene.faces) {
      for (final triangle in face.triangles) {
        final points = triangle.points.map(projection.toCameraSpace).toList();
        final a = points[0], e1 = points[1] - a, e2 = points[2] - a;
        final cross = direction.cross(e2);
        final determinant = e1.dot(cross);
        if (determinant.abs() <=
            1e-12 * e1.length * e2.length * direction.length) {
          continue;
        }
        final fromA = origin - a;
        final u = fromA.dot(cross) / determinant;
        final q = fromA.cross(e1);
        final v = direction.dot(q) / determinant;
        if (u < -1e-10 || v < -1e-10 || u + v > 1 + 1e-10) continue;
        final depth = e2.dot(q) / determinant;
        if (!depth.isFinite || depth < CameraProjection.nearPlane) continue;
        if (nearest == null || depth < nearest) {
          nearest = depth;
          source = face.source;
        }
      }
    }
    if (source == null || nearest == null) return null;
    // Filter only after finding the frontmost visible geometry.
    if (mode == ViewportSelectionMode.planarFace &&
        source.surface is! PlaneSurface) {
      return null;
    }
    final owner = _owners[source]!;
    if (mode == ViewportSelectionMode.body && owner is! Solid) return null;
    return ViewportHit(
      face: source,
      owner: owner,
      depth: nearest,
      point:
          camera.position.vector +
          projection.fromCameraDirection(origin + direction * nearest),
      bodyReference: evaluated.bodies[owner],
      faceReference: evaluated.faces[source],
    );
  }

  ViewportHit? _pickEdge(CameraConfig camera, Size viewport, Offset position) {
    final projection = CameraProjection(camera);
    ViewportHit? nearest;
    var nearestDistance = 7.0 * 7.0;
    for (final entry in scene.edgeSamples.entries) {
      final points = entry.value;
      for (var i = 1; i < points.length; i++) {
        final clipped = projection.clipLine(
          projection.toCameraSpace(points[i - 1]),
          projection.toCameraSpace(points[i]),
          screen: viewport,
        );
        if (clipped == null) continue;
        final a = projection.project(clipped.begin, screen: viewport);
        final b = projection.project(clipped.end, screen: viewport);
        final start = Offset(a.x, a.y), delta = Offset(b.x - a.x, b.y - a.y);
        if (delta.distanceSquared < 1e-12) continue;
        final fromStart = position - start;
        final t =
            ((fromStart.dx * delta.dx + fromStart.dy * delta.dy) /
                    delta.distanceSquared)
                .clamp(0.0, 1.0);
        final closest = start + delta * t;
        final distance = (position - closest).distanceSquared;
        if (distance > nearestDistance + 1e-9) continue;
        final parameter = camera.isOrthographic
            ? t
            : (t / clipped.end.y) /
                  ((1 - t) / clipped.begin.y + t / clipped.end.y);
        final point = clipped.begin * (1 - parameter) + clipped.end * parameter;
        if ((distance - nearestDistance).abs() <= 1e-9 &&
            nearest != null &&
            point.y >= nearest.depth) {
          continue;
        }
        // Test at the edge itself, not at the pointer's offset within the hit
        // tolerance. This keeps silhouette edges selectable from either side.
        final front = pick(
          camera: camera,
          viewport: viewport,
          position: closest,
          mode: ViewportSelectionMode.face,
        );
        if (front != null && front.depth < point.y - point.y.abs() * 1e-6) {
          continue;
        }
        final face = _edgeFaces[entry.key]!;
        final owner = _owners[face]!;
        nearestDistance = distance;
        nearest = ViewportHit(
          face: face,
          edge: entry.key,
          owner: owner,
          depth: point.y,
          point: camera.position.vector + projection.fromCameraDirection(point),
          bodyReference: evaluated.bodies[owner],
          faceReference: evaluated.faces[face],
        );
      }
    }
    return nearest;
  }
}
