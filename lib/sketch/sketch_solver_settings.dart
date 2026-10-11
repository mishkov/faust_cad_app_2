/// Explicit convergence, rank, and work limits for the headless solver.
final class SketchSolverSettings {
  SketchSolverSettings({
    this.distanceTolerance = 1e-8,
    this.angularTolerance = 1e-10,
    this.rankTolerance = 1e-9,
    this.maxIterations = 120,
    this.maxDampingTrials = 20,
    this.maxVariables = 512,
    this.maxEquations = 2048,
  }) {
    if (![
          distanceTolerance,
          angularTolerance,
          rankTolerance,
        ].every((v) => v.isFinite && v > 0) ||
        angularTolerance >= 1 ||
        rankTolerance >= 1 ||
        maxIterations < 0 ||
        maxDampingTrials < 1 ||
        maxVariables < 1 ||
        maxEquations < 1) {
      throw ArgumentError('Invalid sketch solver settings');
    }
  }

  /// The absolute length tolerance in model units.
  final double distanceTolerance;

  /// The dimensionless sine/cosine tolerance for line directions.
  final double angularTolerance;

  /// The relative threshold for rank of normalized Jacobian rows.
  final double rankTolerance;
  final int maxIterations;
  final int maxDampingTrials;
  final int maxVariables;
  final int maxEquations;
}
