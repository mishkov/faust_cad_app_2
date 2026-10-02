/// The underlying, untrimmed mathematical geometry of a face.
///
/// Surfaces do not own boundary topology. A face references a surface and the
/// wires that trim it. Subclasses can describe planar or curved geometry.
abstract class CadSurface {
  const new();
}
