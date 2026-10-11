import '../cad_scene/geometry/planar_frame.dart';
import '../cad_scene/geometry/geometry_tolerance.dart';
import 'sketch_definition.dart';
import 'sketch_solve_result.dart';
import 'sketch_solver.dart';
import 'solved_sketch.dart';

/// Independent sketch entities placed on a resolved plane, without CAD topology.
final class SketchGeometry {
  SketchGeometry({
    required this.definition,
    required PlanarFrame frame,
    SketchSolveResult? solution,
  }) : solution = solution ?? const SketchSolver().solve(definition),
       _frame = PlanarFrame(
         origin: frame.origin,
         xAxis: frame.xAxis,
         yAxis: frame.yAxis,
         tolerance: GeometryTolerance(
           distance: frame.tolerance.distance,
           angular: frame.tolerance.angular,
         ),
       ) {
    if (!this.solution.isValid) {
      throw ArgumentError('SketchGeometry requires a valid solve');
    }
  }

  /// The immutable authored definition with stable entity identities.
  final SketchDefinition definition;

  /// The successful solve classification, residual diagnostics, and freedom.
  final SketchSolveResult solution;

  /// The derived coordinates used by downstream features.
  SolvedSketch get solved => solution.geometry!;
  final PlanarFrame _frame;

  /// The resolved placement, returned as an independent frame.
  PlanarFrame get frame => PlanarFrame(
    origin: _frame.origin,
    xAxis: _frame.xAxis,
    yAxis: _frame.yAxis,
    tolerance: _frame.tolerance,
  );
}
