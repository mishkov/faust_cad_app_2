import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/face_orientation.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A portion of [surface] bounded by [outerWire], excluding [innerWires].
///
/// The face references the original surface and wires without copying their
/// geometry. Boundaries must be topologically closed using shared vertices.
/// [orientation] controls the material normal and effective boundary traversal
/// independently of the surface parameterization and stored wire traversal.
/// Geometric checks such as lying on the surface, self-intersection, and hole
/// containment are the caller's responsibility.
class Face extends CadPrimitive {
  final CadSurface surface;

  /// Material-side orientation, independent of surface parameters and wire data.
  final FaceOrientation orientation;

  final Wire outerWire;
  final List<Wire> innerWires;

  new({
    required this.surface,
    this.orientation = FaceOrientation.forward,
    required this.outerWire,
    List<Wire> innerWires = const [],
  }) : innerWires = List<Wire>.unmodifiable(innerWires) {
    if (!outerWire.isClosed) {
      throw ArgumentError.value(outerWire, 'outerWire', 'Must be closed');
    }
    for (final wire in this.innerWires) {
      if (!wire.isClosed) {
        throw ArgumentError.value(
          innerWires,
          'innerWires',
          'Must all be closed',
        );
      }
    }
  }

  /// Applies this face's orientation to a surface normal, returning a copy.
  Vector3 orientedNormal(Vector3 surfaceNormal) =>
      surfaceNormal * (orientation == FaceOrientation.forward ? 1 : -1);

  /// Reverses material orientation, retaining all geometry and boundary topology.
  Face reversed() => Face(
    surface: surface,
    outerWire: outerWire,
    innerWires: innerWires,
    orientation: orientation == FaceOrientation.forward
        ? FaceOrientation.reversed
        : FaceOrientation.forward,
  );
}
