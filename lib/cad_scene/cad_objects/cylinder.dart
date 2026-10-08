import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/src/cylindrical_solid_builder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';

/// A reference cylinder with exact circular caps and analytic wall patches.
///
/// The base center is [frame]'s origin, and positive [height] extends along its
/// normal. This fixture builds topology independently of sketches or rendering.
class Cylinder extends CadObject {
  /// Creates a fixture with finite positive dimensions and at least two patches.
  Cylinder({
    required this.frame,
    required this.radius,
    required this.height,
    this.patchCount = 4,
  }) {
    validateCylindricalDimensions(
      radius: radius,
      height: height,
      patchCount: patchCount,
    );
  }

  /// The immutable base frame and axis placement.
  final PlanarFrame frame;

  /// The positive radius in model units.
  final double radius;

  /// The positive axial length in model units.
  final double height;

  /// The number of analytic wall patches around the circumference.
  final int patchCount;

  /// Builds a fresh solid with one closed shell and shared boundary topology.
  @override
  List<Solid> build() => [
    buildCylindricalSolid(
      frame: frame,
      radius: radius,
      height: height,
      patchCount: patchCount,
    ),
  ];
}
