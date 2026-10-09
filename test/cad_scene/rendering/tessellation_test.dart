import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/tube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  test('sampling bounds sagitta, respects signed long arcs and reversal', () {
    final circle = CircularCadCurve(frame: PlanarFrame.xy(), radius: 7);
    final edge = Edge(
      Vertex(circle.evaluate(0.4)),
      Vertex(circle.evaluate(0.4 - 1.7 * math.pi)),
      curve: circle,
      trim: CircularTrim(startAngle: 0.4, sweepAngle: -1.7 * math.pi),
    );
    final scene = SceneTessellator().build([
      Objects([edge, edge.reversed()]),
    ], settings: TessellationSettings(chordError: 0.002));
    final samples = scene.edges.first.points;
    expect(scene.edges.last.points, orderedEquals(samples.reversed));
    for (var i = 0; i < samples.length - 1; i++) {
      final midpoint = (samples[i] + samples[i + 1]) / 2;
      expect(7 - midpoint.length, lessThanOrEqualTo(0.002 + 1e-12));
      expect(samples[i].length, closeTo(7, 1e-12));
    }
    expect(samples[samples.length ~/ 2].x, lessThan(0));
    expect(edge.curve, same(circle));
  });

  for (final count in [2, 3, 4, 7]) {
    test(
      'tube $count patches: shared rims, no patch seams, annular area and oriented normals',
      () {
        final solid = Tube(
          frame: PlanarFrame.xy(),
          outerRadius: 3,
          innerRadius: 1,
          height: 5,
          patchCount: count,
        ).build().single;
        final scene = SceneTessellator().build([
          Objects([solid]),
        ]);
        expect(scene.faces, hasLength(2 + 2 * count));
        // Each cap/wall use retains its arc outline; axial seam uses are omitted.
        expect(scene.edges, hasLength(8 * count));
        for (final face in scene.faces) {
          if (face.source.surface is PlaneSurface) {
            var area = 0.0;
            for (final tri in face.triangles) {
              area +=
                  (tri.points[1] - tri.points[0])
                      .cross(tri.points[2] - tri.points[0])
                      .length /
                  2;
              final center =
                  (tri.points[0] + tri.points[1] + tri.points[2]) / 3;
              expect(
                math.sqrt(center.x * center.x + center.y * center.y),
                greaterThan(0.98),
              );
            }
            expect(area, closeTo(math.pi * 8, 0.2));
          } else {
            final surface = face.source.surface as CylinderSurface;
            for (final tri in face.triangles) {
              for (var i = 0; i < 3; i++) {
                final expected = face.source.orientedNormal(
                  surface.normal(math.atan2(tri.points[i].y, tri.points[i].x)),
                );
                expect((tri.normals[i] - expected).length, lessThan(1e-10));
              }
            }
            for (final p
                in face.loops
                    .expand((l) => l)
                    .where((p) => p.z == 0 || p.z == 5)) {
              expect(
                scene.faces
                    .take(2)
                    .any(
                      (cap) => cap.loops.expand((l) => l).any((q) => q == p),
                    ),
                isTrue,
              );
            }
          }
        }
        expect(solid.shells.single.isClosed, isTrue);
        expect(
          solid.shells.single.faces
              .expand((f) => f.outerWire.edges)
              .any((e) => e.curve is CircularCadCurve),
          isTrue,
        );
      },
    );
  }

  test('cylindrical mesh interior meets the same model-space error bound', () {
    final frame = PlanarFrame.fromPlane(
      plane: PlaneSurface(origin: Vector3(5, -2, 4), normal: Vector3(1, 2, 3)),
      preferredDirection: Vector3(1, 0, 0),
    );
    final mesh = SceneTessellator().build([
      Cylinder(frame: frame, radius: 8, height: 12),
    ], settings: TessellationSettings(chordError: 0.003));
    for (final face in mesh.faces.where(
      (f) => f.source.surface is CylinderSurface,
    )) {
      for (final tri in face.triangles) {
        final probes = [
          ...tri.points,
          for (var i = 0; i < 3; i++)
            (tri.points[i] + tri.points[(i + 1) % 3]) / 2,
          tri.points.reduce((a, b) => a + b) / 3,
        ];
        for (final p in probes) {
          final delta = p - frame.origin;
          final radial = delta - frame.normal * delta.dot(frame.normal);
          expect((8 - radial.length).abs(), lessThanOrEqualTo(0.003 + 1e-10));
        }
      }
    }
  });

  test(
    'concave planar face with multiple holes triangulates only material',
    () {
      Wire polygon(List<Vector3> points) {
        final vertices = points.map(Vertex.new).toList();
        return Wire([
          for (var i = 0; i < vertices.length; i++)
            Edge(
              vertices[i],
              vertices[(i + 1) % vertices.length],
              curve: const LinearCadCurve(),
            ),
        ]);
      }

      Wire rectangle(double x, double y) => polygon([
        Vector3(x, y, 0),
        Vector3(x + 1, y, 0),
        Vector3(x + 1, y + 1, 0),
        Vector3(x, y + 1, 0),
      ]);
      final face = Face(
        surface: PlanarFrame.xy().plane,
        outerWire: polygon([
          Vector3(0, 0, 0),
          Vector3(6, 0, 0),
          Vector3(6, 2, 0),
          Vector3(2, 2, 0),
          Vector3(2, 6, 0),
          Vector3(0, 6, 0),
        ]),
        innerWires: [rectangle(3, 0.5), rectangle(0.5, 3)],
      );
      final triangles = SceneTessellator()
          .build([
            Objects([face]),
          ])
          .faces
          .single
          .triangles;
      final area = triangles.fold(
        0.0,
        (sum, t) =>
            sum +
            (t.points[1] - t.points[0])
                    .cross(t.points[2] - t.points[0])
                    .length /
                2,
      );
      expect(area, closeTo(18, 1e-12));
      for (final tri in triangles) {
        final p = tri.points.reduce((a, b) => a + b) / 3;
        expect(p.x > 2 && p.y > 2, isFalse);
        expect(p.x > 3 && p.x < 4 && p.y > 0.5 && p.y < 1.5, isFalse);
        expect(p.x > 0.5 && p.x < 1.5 && p.y > 3 && p.y < 4, isFalse);
      }
    },
  );

  test('cache reuses fresh builds and invalidates quality, revision, and mutable vertices', () {
    final cache = SceneTessellator();
    final cylinder = Cylinder(frame: PlanarFrame.xy(), radius: 3, height: 8);
    final a = cache.build([cylinder]);
    expect(cache.build([cylinder]), same(a));
    final finer = cache.build([
      cylinder,
    ], settings: TessellationSettings(chordError: 0.001));
    expect(finer, isNot(same(a)));
    expect(
      finer.faces.last.triangles.length,
      greaterThan(a.faces.last.triangles.length),
    );
    final revised = cache.build([cylinder], geometryRevision: 1);
    expect(cache.build([cylinder], geometryRevision: 1), same(revised));
    cache.invalidateGeometry();
    expect(cache.build([cylinder], geometryRevision: 1), isNot(same(revised)));
    final begin = Vertex(Vector3.zero()), end = Vertex(Vector3(1, 0, 0));
    final line = Objects([Edge(begin, end, curve: const LinearCadCurve())]);
    final before = cache.build([line]);
    end.vector.x = 2;
    final after = cache.build([line]);
    expect(after, isNot(same(before)));
    expect(before.edges.single.points.last.x, 1);
    expect(after.edges.single.points.last.x, 2);
  });

  test('budgets reject excessive work without silently relaxing accuracy', () {
    expect(() => TessellationSettings(chordError: 0), throwsArgumentError);
    expect(() => TessellationSettings(maxAngle: math.pi), throwsArgumentError);
    final cylinder = Cylinder(frame: PlanarFrame.xy(), radius: 3, height: 8);
    expect(
      () => SceneTessellator().build(
        [cylinder],
        settings: TessellationSettings(
          chordError: 1e-12,
          maxSegmentsPerEdge: 20,
        ),
      ),
      throwsStateError,
    );
    expect(
      () => SceneTessellator().build([
        cylinder,
      ], settings: TessellationSettings(maxTriangles: 2)),
      throwsStateError,
    );
  });

  test(
    'an isolated cylindrical patch retains axial borders and standalone seams',
    () {
      final solid = Cylinder(
        frame: PlanarFrame.xy(),
        radius: 3,
        height: 8,
      ).build().single;
      final patch = solid.shells.single.faces.last;
      final cache = SceneTessellator();
      expect(
        cache.build([
          Objects([patch]),
        ]).edges,
        hasLength(4),
      );
      final seam = patch.outerWire.edges.firstWhere(
        (e) => e.curve is LinearCadCurve,
      );
      final scene = cache.build([
        Objects([solid, seam]),
      ]);
      expect(scene.edges.where((e) => !e.boundary), hasLength(1));
    },
  );

  test('trimmed cylindrical patch supports an angular/axial window', () {
    final surface = CylinderSurface(frame: PlanarFrame.xy(), radius: 3);
    Wire rectangle(double a, double b, double low, double high) {
      final bottom = CircularCadCurve(
        frame: PlanarFrame.xy(origin: Vector3(0, 0, low)),
        radius: 3,
      );
      final top = CircularCadCurve(
        frame: PlanarFrame.xy(origin: Vector3(0, 0, high)),
        radius: 3,
      );
      final vertices = [
        Vertex(surface.evaluate(a, low)),
        Vertex(surface.evaluate(b, low)),
        Vertex(surface.evaluate(b, high)),
        Vertex(surface.evaluate(a, high)),
      ];
      return Wire([
        Edge(
          vertices[0],
          vertices[1],
          curve: bottom,
          trim: CircularTrim(startAngle: a, sweepAngle: b - a),
        ),
        Edge(vertices[1], vertices[2], curve: const LinearCadCurve()),
        Edge(
          vertices[2],
          vertices[3],
          curve: top,
          trim: CircularTrim(startAngle: b, sweepAngle: a - b),
        ),
        Edge(vertices[3], vertices[0], curve: const LinearCadCurve()),
      ]);
    }

    final face = Face(
      surface: surface,
      outerWire: rectangle(-0.8, 0.8, 0, 5),
      innerWires: [rectangle(-0.2, 0.2, 2, 3)],
    );
    final mesh = SceneTessellator()
        .build([
          Objects([face]),
        ])
        .faces
        .single;
    for (final triangle in mesh.triangles) {
      final p = triangle.points.reduce((a, b) => a + b) / 3;
      final theta = math.atan2(p.y, p.x);
      expect(theta.abs() < 0.2 - 1e-10 && p.z > 2 && p.z < 3, isFalse);
    }
  });
}

class Objects extends CadObject {
  Objects(this.primitives);
  final List<CadPrimitive> primitives;
  @override
  List<CadPrimitive> build() => primitives;
}
