import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/edge.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';

// Shared implementation for the two reference objects, not a feature command.
void validateCylindricalDimensions({
  required double radius,
  required double height,
  required int patchCount,
}) {
  for (final dimension in [(radius, 'radius'), (height, 'height')]) {
    if (!dimension.$1.isFinite || dimension.$1 <= 0) {
      throw ArgumentError.value(
        dimension.$1,
        dimension.$2,
        'Must be finite and positive',
      );
    }
  }
  if (patchCount < 2) {
    throw ArgumentError.value(patchCount, 'patchCount', 'Must be at least two');
  }
}

Solid buildCylindricalSolid({
  required PlanarFrame frame,
  required double radius,
  required double height,
  required int patchCount,
  double? innerRadius,
}) {
  final topFrame = PlanarFrame(
    origin: finiteVector3Result(frame.origin + frame.normal * height),
    xAxis: frame.xAxis,
    yAxis: frame.yAxis,
    tolerance: frame.tolerance,
  );
  Wire ring(PlanarFrame placement, double r) => Wire.circular(
    CircularCadCurve(frame: placement, radius: r),
    arcCount: patchCount,
  );
  final bottom = ring(frame, radius);
  final top = ring(topFrame, radius);
  final innerBottom = innerRadius == null ? null : ring(frame, innerRadius);
  final innerTop = innerRadius == null ? null : ring(topFrame, innerRadius);
  final faces = [
    Face(
      surface: frame.plane,
      outerWire: bottom,
      innerWires: [if (innerBottom != null) innerBottom.reversed()],
      orientation: FaceOrientation.reversed,
    ),
    Face(
      surface: topFrame.plane,
      outerWire: top,
      innerWires: [if (innerTop != null) innerTop.reversed()],
    ),
    ..._wallFaces(
      CylinderSurface(frame: frame, radius: radius),
      bottom,
      top,
      FaceOrientation.forward,
    ),
    if (innerRadius != null)
      ..._wallFaces(
        CylinderSurface(frame: frame, radius: innerRadius),
        innerBottom!,
        innerTop!,
        FaceOrientation.reversed,
      ),
  ];
  return Solid(shells: [Shell(faces: faces)]);
}

List<Face> _wallFaces(
  CylinderSurface surface,
  Wire bottom,
  Wire top,
  FaceOrientation orientation,
) {
  final count = bottom.edges.length;
  final axialEdges = [
    for (var i = 0; i < count; i++)
      Edge(
        bottom.edges[i].begin,
        top.edges[i].begin,
        curve: const LinearCadCurve(),
      ),
  ];
  for (final edge in axialEdges) {
    if (edge.begin.vector == edge.end.vector) {
      throw ArgumentError('Height is too small to resolve at this placement');
    }
  }
  return [
    for (var i = 0; i < count; i++)
      Face(
        surface: surface,
        orientation: orientation,
        outerWire: Wire([
          bottom.edges[i],
          axialEdges[(i + 1) % count],
          top.edges[i].reversed(),
          axialEdges[i].reversed(),
        ]),
      ),
  ];
}
