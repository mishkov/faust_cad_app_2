import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/render_triangle.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellated_scene.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/trimmed_polygon.dart';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

/// A bounded, one-scene cache independent of camera and render mode.
///
/// Snapshot comparison detects mutable vertices and objects whose build() returns
/// fresh topology. Revision/invalidateGeometry support explicit caller updates.
/// Quality changes invalidate all samples and meshes together.
class SceneTessellator {
  List<Object>? _snapshot;
  TessellationSettings? _settings;
  Object? _revision;
  TessellatedScene? _cached;

  void invalidateGeometry() {
    _snapshot = null;
    _cached = null;
  }

  TessellatedScene build(
    List<CadObject> objects, {
    TessellationSettings? settings,
    Object? geometryRevision,
  }) {
    return buildGeometry(
      [for (final object in objects) ...object.build()],
      settings: settings,
      geometryRevision: geometryRevision,
    );
  }

  TessellatedScene buildGeometry(
    List<CadPrimitive> geometry, {
    TessellationSettings? settings,
    Object? geometryRevision,
  }) {
    final quality = settings ?? TessellationSettings.defaults;
    final faces = <Face>[];
    final uses = <({Edge edge, Face? face})>[];
    final snapshot = <Object>[];
    final identities = Map<Object, int>.identity();
    int id(Object object) =>
        identities.putIfAbsent(object, () => identities.length);
    void vector(Vector3 p) => snapshot.addAll([p.x, p.y, p.z]);
    void frame(PlanarFrame f) {
      vector(f.origin);
      vector(f.xAxis);
      vector(f.yAxis);
      snapshot.addAll([f.tolerance.distance, f.tolerance.angular]);
    }

    void collect(CadPrimitive p, [Face? owner]) {
      snapshot.add(p.runtimeType);
      switch (p) {
        case Solid(:final shells):
          snapshot.add(shells.length);
          for (final s in shells) {
            collect(s);
          }
        case Shell(:final faces):
          snapshot.add(faces.length);
          for (final f in faces) {
            collect(f);
          }
        case Face():
          faces.add(p);
          snapshot.addAll([
            id(p.surface),
            p.surface.runtimeType,
            p.orientation,
            p.innerWires.length,
          ]);
          final surface = p.surface;
          if (surface is PlaneSurface) {
            vector(surface.origin);
            vector(surface.normal);
          }
          if (surface is CylinderSurface) {
            frame(surface.frame);
            snapshot.add(surface.radius);
          }
          collect(p.outerWire, p);
          for (final w in p.innerWires) {
            collect(w, p);
          }
        case Wire(:final edges):
          snapshot.add(edges.length);
          for (final e in edges) {
            collect(e, owner);
          }
        case Edge():
          uses.add((edge: p, face: owner));
          snapshot.addAll([id(p.begin), id(p.end), p.curve.runtimeType]);
          vector(p.begin.vector);
          vector(p.end.vector);
          if (p.curve case CircularCadCurve circle) {
            snapshot.addAll([
              id(circle),
              circle.radius,
              p.trim!.startAngle,
              p.trim!.sweepAngle,
            ]);
            frame(circle.frame);
          }
      }
    }

    snapshot.add(geometry.length);
    for (final primitive in geometry) {
      collect(primitive);
    }
    if (_cached != null &&
        _settings == quality &&
        _revision == geometryRevision &&
        listEquals(_snapshot, snapshot)) {
      return _cached!;
    }

    // Index by shared vertex identity first, so boundary lookup stays local.
    final samples =
        Map<Object, List<({Edge edge, List<Vector3> points})>>.identity();
    List<Vector3> sample(Edge edge) {
      final bucket = samples[edge.begin] ?? const [];
      for (final previous in bucket) {
        if (edge.hasSameBoundary(previous.edge)) {
          return identical(edge.begin, previous.edge.begin)
              ? previous.points
              : List.unmodifiable(previous.points.reversed);
        }
      }
      final circle = edge.curve;
      final count = circle is CircularCadCurve
          ? quality.segments(circle.radius, edge.trim!.sweepAngle)
          : 1;
      if (circle is CircularCadCurve && !edge.hasValidCircularEndpoints) {
        throw StateError(
          'Circular endpoints changed outside analytic tolerance',
        );
      }
      final points = List<Vector3>.unmodifiable([
        edge.begin.vector.clone(),
        for (var i = 1; i < count; i++) edge.evaluate(i / count),
        edge.end.vector.clone(),
      ]);
      final entry = (edge: edge, points: points);
      (samples[edge.begin] ??= []).add(entry);
      (samples[edge.end] ??= []).add(entry);
      return points;
    }

    bool supported(Edge e) =>
        e.curve is LinearCadCurve || e.curve is CircularCadCurve;
    final rendered = <TessellatedFace>[];
    var remaining = quality.maxTriangles;
    for (final face in faces) {
      final wires = [face.outerWire, ...face.innerWires];
      if (wires.any((w) => w.edges.any((e) => !supported(e)))) continue;
      final surface = face.surface;
      if (surface is! PlaneSurface && surface is! CylinderSurface) continue;
      final loops = [
        for (final wire in wires)
          [for (final e in wire.edges) ...sample(e).take(sample(e).length - 1)],
      ];
      final uvLoops = <List<({Vector2 uv, Vector3 world})>>[];
      if (surface is PlaneSurface) {
        final basis = PlanarFrame.fromPlane(
          plane: surface,
          preferredDirection: surface.normal.x.abs() < 0.9
              ? Vector3(1, 0, 0)
              : Vector3(0, 1, 0),
        );
        for (final loop in loops) {
          uvLoops.add([
            for (final p in loop) (uv: basis.projectToLocal(p), world: p),
          ]);
        }
      } else if (surface is CylinderSurface) {
        double? outerCenter;
        for (final loop in loops) {
          final uv = <({Vector2 uv, Vector3 world})>[];
          double? previous;
          for (final p in loop) {
            final delta = p - surface.origin;
            var angle = math.atan2(
              delta.dot(surface.frame.yAxis),
              delta.dot(surface.frame.xAxis),
            );
            if (previous != null) {
              angle +=
                  (2 * math.pi) * ((previous - angle) / (2 * math.pi)).round();
            }
            uv.add((uv: Vector2(angle, delta.dot(surface.axis)), world: p));
            previous = angle;
          }
          final center =
              uv.map((p) => p.uv.x).reduce((a, b) => a + b) / uv.length;
          outerCenter ??= center;
          final shift =
              (2 * math.pi) * ((outerCenter - center) / (2 * math.pi)).round();
          uvLoops.add([
            for (final p in uv) (uv: p.uv + Vector2(shift, 0), world: p.world),
          ]);
        }
      }
      final triangles = TrimmedPolygon.triangulate(uvLoops, budget: remaining);
      remaining -= triangles.length;
      rendered.add(
        TessellatedFace(face, loops, [
          for (final tri in triangles)
            RenderTriangle(
              [for (final p in tri) p.world],
              [
                for (final p in tri)
                  face.orientedNormal(
                    surface is CylinderSurface
                        ? surface.normal(p.uv.x)
                        : (surface as PlaneSurface).normal,
                  ),
              ],
            ),
        ]),
      );
    }

    final owners = Map<Object, List<({Edge edge, Face? face})>>.identity();
    for (final use in uses) {
      (owners[use.edge.begin] ??= []).add(use);
      (owners[use.edge.end] ??= []).add(use);
    }
    bool isSeam(({Edge edge, Face? face}) use) {
      final face = use.face;
      if (face == null ||
          face.surface is! CylinderSurface ||
          use.edge.curve is! LinearCadCurve) {
        return false;
      }
      final matching = (owners[use.edge.begin] ?? [])
          .where(
            (other) =>
                other.face != null && use.edge.hasSameBoundary(other.edge),
          )
          .toList();
      return matching.length == 2 &&
          matching.every(
            (other) =>
                identical(other.face!.surface, face.surface) &&
                other.face!.orientation == face.orientation,
          );
    }

    final renderEdges = [
      for (final use in uses)
        if (supported(use.edge) && !isSeam(use))
          (points: sample(use.edge), boundary: use.face != null),
    ];
    final result = TessellatedScene(rendered, renderEdges);
    _snapshot = snapshot;
    _settings = quality;
    _revision = geometryRevision;
    _cached = result;
    return result;
  }
}
