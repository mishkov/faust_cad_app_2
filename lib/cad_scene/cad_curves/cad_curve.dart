/// Underlying curve geometry, independent of a bounded topological edge.
///
/// Analytic curves define their own parameter convention; edge trims and
/// traversal are stored on the edge, not on the curve.
abstract class CadCurve {
  const new();
}
