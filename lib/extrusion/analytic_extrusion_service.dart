import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../cad_scene/cad_curves/circular_cad_curve.dart';
import '../cad_scene/cad_curves/circular_trim.dart';
import '../cad_scene/cad_curves/linear_cad_curve.dart';
import '../cad_scene/cad_primitivies/edge.dart';
import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/cad_primitivies/face_orientation.dart';
import '../cad_scene/cad_primitivies/shell.dart';
import '../cad_scene/cad_primitivies/solid.dart';
import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/cad_primitivies/wire.dart';
import '../cad_scene/cad_surfaces/cylinder_surface.dart';
import '../cad_scene/cad_surfaces/plane_surface.dart';
import '../cad_scene/geometry/planar_frame.dart';
import '../planar_regions/planar_regions.dart';
import 'extruded_volume.dart';
import 'extrusion_diagnostic.dart';
import 'extrusion_face_output.dart';
import 'extrusion_result.dart';

/// Extrudes selected validated analytic cells without scene or history state.
class AnalyticExtrusionService {
  /// Creates a stateless service.
  const AnalyticExtrusionService();

  /// Unions cells from one arrangement, placed in one plane with common settings.
  ///
  /// Duplicate IDs are idempotent. Empty/unknown selections, unusable profiles,
  /// point contacts, and unrepresentable geometry return structured diagnostics.
  /// Positive [distance] runs along [frame.normal], negated by [reverse].
  ExtrusionResult extrude({
    required RegionResult regions,
    required Iterable<String> regionIds,
    required PlanarFrame frame,
    required double distance,
    bool reverse = false,
  }) {
    final ids = regionIds.toSet().toList()..sort();
    final diagnostics = [
      for (final d in regions.diagnostics)
        ExtrusionDiagnostic(
          d.code,
          d.message,
          isError: d.isError,
          inputIds: d.inputIds,
        ),
    ];
    void reject(String code, String message) =>
        diagnostics.add(ExtrusionDiagnostic(code, message, regionIds: ids));
    if (!distance.isFinite || distance <= 0) {
      reject(
        'invalidDistance',
        'Extrusion distance must be finite and positive',
      );
    }
    if (!regions.isValid) {
      reject('invalidProfile', 'The planar arrangement is unavailable');
    }
    if (ids.isEmpty) {
      reject('emptySelection', 'Select at least one planar cell');
    }
    final unknown = ids.where((id) => !regions.regions.any((r) => r.id == id));
    if (unknown.isNotEmpty) {
      diagnostics.add(
        ExtrusionDiagnostic(
          'unknownRegion',
          'Selection contains unavailable region IDs',
          regionIds: unknown,
        ),
      );
    }
    if (diagnostics.any((d) => d.isError)) {
      return ExtrusionResult(diagnostics: diagnostics);
    }
    final selection = regions.union(ids);
    diagnostics.addAll([
      for (final d in selection.diagnostics)
        ExtrusionDiagnostic(
          d.code,
          d.message,
          isError: d.isError,
          regionIds: ids,
          inputIds: d.inputIds,
        ),
    ]);
    if (!selection.isValid) return ExtrusionResult(diagnostics: diagnostics);
    try {
      final signedDistance = reverse ? -distance : distance;
      final endFrame = PlanarFrame(
        origin: frame.origin + frame.normal * signedDistance,
        xAxis: frame.xAxis,
        yAxis: frame.yAxis,
        tolerance: frame.tolerance,
      );
      if (endFrame.origin == frame.origin) {
        throw StateError('Distance cannot be represented at this placement');
      }
      final volumes = <ExtrudedVolume>[];
      final worldVertices = <(double, double, double)>{};
      final referencesByComponent = <String, List<RegionReference>>{
        for (final profile in selection.regions) profile.id: [],
      };
      for (final cell in regions.regions.where((r) => ids.contains(r.id))) {
        final interior = _interiorPoint(cell);
        final owners = selection.regions
            .where((p) => p.locate(interior) == RegionPointLocation.inside)
            .toList();
        if (owners.length != 1) {
          throw StateError(
            'Cannot resolve selected cell to one material component',
          );
        }
        referencesByComponent[owners.single.id]!.add(
          regions.reference(cell.id),
        );
      }
      for (final profile in selection.regions) {
        final volume = profile.area * distance;
        if (!volume.isFinite || volume <= 0) {
          throw StateError('Material volume is outside finite positive range');
        }
        volumes.add(
          _build(
            profile,
            referencesByComponent[profile.id]!,
            frame,
            endFrame,
            reverse,
            worldVertices,
          ),
        );
      }
      return ExtrusionResult(volumes: volumes, diagnostics: diagnostics);
    } on ArgumentError catch (error) {
      reject('unrepresentableGeometry', error.toString());
    } on StateError catch (error) {
      reject('unrepresentableGeometry', error.message);
    }
    return ExtrusionResult(diagnostics: diagnostics);
  }

  // Sample strictly inside the selected cell, rather than on a rounded arc
  // boundary. The local left side is material for both outer and hole loops.
  // This query never moves model geometry or uses the model gap tolerance.
  Vector2 _interiorPoint(PlanarRegion cell) {
    for (final portion in cell.outer.portions) {
      final midpoint = portion.pointAt(0.5);
      final tangent = portion.isArc
          ? Vector2(
                  -math.sin(portion.startAngle! + portion.sweepAngle! / 2),
                  math.cos(portion.startAngle! + portion.sweepAngle! / 2),
                ) *
                (portion.radius! * portion.sweepAngle!)
          : portion.end - portion.start;
      final left = Vector2(-tangent.y, tangent.x)..normalize();
      var step = tangent.length * 0.01;
      for (var attempt = 0; attempt < 64 && step > 0; attempt++) {
        final point = midpoint + left * step;
        if (cell.locate(point) == RegionPointLocation.inside) return point;
        step /= 2;
      }
    }
    throw StateError('No representable interior sample for selected cell');
  }

  ExtrudedVolume _build(
    PlanarRegion profile,
    List<RegionReference> references,
    PlanarFrame frame,
    PlanarFrame endFrame,
    bool reverse,
    Set<(double, double, double)> worldVertices,
  ) {
    final key = 'volume:${profile.id}';
    final startWires = <Wire>[], endWires = <Wire>[];
    final walls = <ExtrusionFaceOutput>[];
    final loops = [profile.outer, ...profile.holes];
    PlanarFrame circleFrame(PlanarFrame placement, BoundaryPortion p) =>
        PlanarFrame(
          origin: placement.localToWorld(p.center!),
          xAxis: placement.xAxis,
          yAxis: placement.yAxis,
          tolerance: placement.tolerance,
        );
    for (var loopIndex = 0; loopIndex < loops.length; loopIndex++) {
      final portions = loops[loopIndex].portions;
      final start = [
        for (final p in portions) Vertex(frame.localToWorld(p.start)),
      ];
      final end = [
        for (final p in portions) Vertex(endFrame.localToWorld(p.start)),
      ];
      for (final vertex in [...start, ...end]) {
        final p = vertex.vector;
        if (!worldVertices.add((p.x, p.y, p.z))) {
          throw StateError(
            'Distinct boundary vertices collapsed in world space',
          );
        }
      }
      final axial = [
        for (var i = 0; i < portions.length; i++)
          Edge(start[i], end[i], curve: const LinearCadCurve()),
      ];
      final bottomEdges = <Edge>[], topEdges = <Edge>[];
      for (var i = 0; i < portions.length; i++) {
        final next = (i + 1) % portions.length;
        final p = portions[i];
        Edge edge(List<Vertex> vertices, PlanarFrame placement) => Edge(
          vertices[i],
          vertices[next],
          curve: p.isArc
              ? CircularCadCurve(
                  frame: circleFrame(placement, p),
                  radius: p.radius!,
                )
              : const LinearCadCurve(),
          trim: p.isArc
              ? CircularTrim(
                  startAngle: p.startAngle!,
                  sweepAngle: p.sweepAngle!,
                )
              : null,
        );
        bottomEdges.add(edge(start, frame));
        topEdges.add(edge(end, endFrame));
      }
      startWires.add(Wire(bottomEdges));
      endWires.add(Wire(topEdges));
      for (var i = 0; i < portions.length; i++) {
        final p = portions[i];
        final inwardCylinder = p.isArc && p.sweepAngle! < 0;
        final wire = Wire([
          bottomEdges[i],
          axial[(i + 1) % portions.length],
          topEdges[i].reversed(),
          axial[i].reversed(),
        ]);
        // Cylinder parameters always point radially outward. Negative profile
        // sweeps need reversed material orientation; negative extrusion also
        // reverses the wire to keep effective traversal consistent with caps.
        final face = Face(
          surface: p.isArc
              ? CylinderSurface(frame: circleFrame(frame, p), radius: p.radius!)
              : PlaneSurface(
                  origin: start[i].vector,
                  normal:
                      (start[(i + 1) % portions.length].vector -
                              start[i].vector)
                          .cross(frame.normal),
                ),
          orientation: inwardCylinder
              ? FaceOrientation.reversed
              : FaceOrientation.forward,
          outerWire: reverse != inwardCylinder ? wire.reversed() : wire,
        );
        walls.add(
          ExtrusionFaceOutput(
            key: '$key:wall:$loopIndex:$i',
            face: face,
            role: ExtrusionFaceRole.wall,
            regions: references,
            boundaries: [p],
          ),
        );
      }
    }
    final boundaries = loops.expand((l) => l.portions).toList();
    final caps = [
      ExtrusionFaceOutput(
        key: '$key:startCap',
        role: ExtrusionFaceRole.startCap,
        regions: references,
        boundaries: boundaries,
        face: Face(
          surface: frame.plane,
          outerWire: startWires.first,
          innerWires: startWires.skip(1).toList(),
          orientation: reverse
              ? FaceOrientation.forward
              : FaceOrientation.reversed,
        ),
      ),
      ExtrusionFaceOutput(
        key: '$key:endCap',
        role: ExtrusionFaceRole.endCap,
        regions: references,
        boundaries: boundaries,
        face: Face(
          surface: endFrame.plane,
          outerWire: endWires.first,
          innerWires: endWires.skip(1).toList(),
          orientation: reverse
              ? FaceOrientation.reversed
              : FaceOrientation.forward,
        ),
      ),
    ];
    final outputs = [...caps, ...walls];
    return ExtrudedVolume(
      key: key,
      profile: profile,
      solid: Solid(shells: [Shell(faces: outputs.map((o) => o.face).toList())]),
      faces: outputs,
    );
  }
}
