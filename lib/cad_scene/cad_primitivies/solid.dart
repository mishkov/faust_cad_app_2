import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/shell.dart';

/// A 3D volume bounded by one outer shell and optional inner cavity shells.
///
/// The first entry in [shells] is the outer boundary; subsequent entries bound
/// enclosed regions where material is absent. Shells and their geometry are
/// referenced without copying. Each shell must have closed manifold topology.
/// Geometric validity, including non-zero volume, self-intersection, cavity
/// containment, and outward/inward surface orientation, is the caller's
/// responsibility.
class Solid extends CadPrimitive {
  final List<Shell> shells;

  new({required List<Shell> shells})
    : shells = List<Shell>.unmodifiable(shells) {
    if (this.shells.isEmpty) {
      throw ArgumentError.value(
        shells,
        'shells',
        'A solid needs an outer shell',
      );
    }
    final seen = Set<Shell>.identity();
    for (final shell in this.shells) {
      if (!seen.add(shell)) {
        throw ArgumentError.value(shells, 'shells', 'Shells must be distinct');
      }
      if (!shell.isClosed) {
        throw ArgumentError.value(
          shells,
          'shells',
          'Every shell must form a closed manifold boundary',
        );
      }
    }
  }
}
