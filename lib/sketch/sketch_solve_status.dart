/// The result of a bounded solve and local differential freedom analysis.
enum SketchSolveStatus {
  underconstrained,
  fullyConstrained,
  redundant,
  conflicting,
  numericalFailure,
}
