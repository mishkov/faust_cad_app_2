import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/wire.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cad_surface.dart';

/// A portion of [surface] bounded by [outerWire], excluding [innerWires].
///
/// The face references the original surface and wires without copying their
/// geometry. Boundaries must be topologically closed using shared vertices.
/// Geometric checks such as lying on the surface, self-intersection, and hole
/// containment are the caller's responsibility.
class Face extends CadPrimitive {
  final CadSurface surface;
  final Wire outerWire;
  final List<Wire> innerWires;

  new({
    required this.surface,
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
}
