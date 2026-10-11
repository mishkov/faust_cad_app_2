import 'constraints/sketch_constraint_id.dart';

/// A constraint-specific residual or a solver-wide numerical diagnostic.
final class SketchConstraintDiagnostic {
  const SketchConstraintDiagnostic({
    this.constraintId,
    required this.code,
    required this.message,
    this.residual,
    this.tolerance,
  });
  final SketchConstraintId? constraintId;
  final String code;
  final String message;

  /// The maximum absolute residual in model units or dimensionless angle units.
  final double? residual;
  final double? tolerance;
}
