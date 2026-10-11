import '../cad_scene/geometry/planar_frame.dart';
import '../cad_scene/geometry/geometry_tolerance.dart';
import 'sketch_definition.dart';

/// Independent sketch entities placed on a resolved plane, without CAD topology.
final class SketchGeometry {
  SketchGeometry({required this.definition, required PlanarFrame frame})
    : _frame = PlanarFrame(
        origin: frame.origin,
        xAxis: frame.xAxis,
        yAxis: frame.yAxis,
        tolerance: GeometryTolerance(
          distance: frame.tolerance.distance,
          angular: frame.tolerance.angular,
        ),
      );

  /// The immutable authored definition with stable entity identities.
  final SketchDefinition definition;
  final PlanarFrame _frame;

  /// The resolved placement, returned as an independent frame.
  PlanarFrame get frame => PlanarFrame(
    origin: _frame.origin,
    xAxis: _frame.xAxis,
    yAxis: _frame.yAxis,
    tolerance: _frame.tolerance,
  );
}
