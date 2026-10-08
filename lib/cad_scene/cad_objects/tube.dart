import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/src/cylindrical_solid_builder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';

/// A reference hollow tube with annular caps and an open bore at both ends.
///
/// The base center is [frame]'s origin, and [height] extends along its normal.
/// Outer walls face radially outward; inner walls face into the through-hole.
/// All faces belong to one shell, with no enclosed cavity shell.
class Tube extends CadObject {
  /// Creates a fixture with `0 < innerRadius < outerRadius` and positive height.
  ///
  /// Dimensions must be finite and [patchCount] must be at least two.
  Tube({
    required this.frame,
    required this.outerRadius,
    required this.innerRadius,
    required this.height,
    this.patchCount = 4,
  }) {
    validateCylindricalDimensions(
      radius: outerRadius,
      height: height,
      patchCount: patchCount,
    );
    if (!innerRadius.isFinite ||
        innerRadius <= 0 ||
        innerRadius >= outerRadius) {
      throw ArgumentError.value(
        innerRadius,
        'innerRadius',
        'Must be finite, positive, and less than outerRadius',
      );
    }
  }

  /// The immutable base frame and axis placement.
  final PlanarFrame frame;

  /// The positive outer wall radius in model units.
  final double outerRadius;

  /// The positive bore radius, strictly less than [outerRadius].
  final double innerRadius;

  /// The positive axial length in model units.
  final double height;

  /// The number of analytic patches around each wall.
  final int patchCount;

  /// Builds a fresh solid with one closed shell surrounding the through-hole.
  @override
  List<Solid> build() => [
    buildCylindricalSolid(
      frame: frame,
      radius: outerRadius,
      innerRadius: innerRadius,
      height: height,
      patchCount: patchCount,
    ),
  ];
}
