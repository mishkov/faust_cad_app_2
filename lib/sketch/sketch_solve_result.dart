import 'constraints/sketch_constraint_id.dart';
import 'sketch_constraint_diagnostic.dart';
import 'sketch_solve_status.dart';
import 'solved_sketch.dart';

/// A solve outcome whose geometry is published only when constraints are valid.
final class SketchSolveResult {
  SketchSolveResult({
    required this.status,
    required this.iterations,
    this.geometry,
    this.degreesOfFreedom,
    this.rank,
    Iterable<SketchConstraintId> redundantConstraintIds = const [],
    Iterable<SketchConstraintDiagnostic> diagnostics = const [],
  }) : redundantConstraintIds = List.unmodifiable(redundantConstraintIds),
       diagnostics = List.unmodifiable(diagnostics);

  final SketchSolveStatus status;
  final int iterations;
  final SolvedSketch? geometry;

  /// The local differential freedom, including free translation and rotation.
  ///
  /// Unavailable for failed solves. Redundant sketches may still have freedom.
  final int? degreesOfFreedom;
  final int? rank;
  final List<SketchConstraintId> redundantConstraintIds;
  final List<SketchConstraintDiagnostic> diagnostics;

  /// Encodes inspection diagnostics without publishing failed geometry.
  Map<String, Object?> toDiagnostics() => {
    'status': status.name,
    'iterations': iterations,
    'degreesOfFreedom': degreesOfFreedom,
    'rank': rank,
    'redundantConstraintIds': redundantConstraintIds
        .map((id) => id.value)
        .toList(),
    'diagnostics': diagnostics
        .map(
          (d) => {
            'constraintId': d.constraintId?.value,
            'code': d.code,
            'message': d.message,
            'residual': d.residual,
            'tolerance': d.tolerance,
          },
        )
        .toList(),
  };

  bool get isValid => geometry != null;
}
