import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/geometry/planar_frame.dart';
import 'topology_copy.dart';

// The frame is infinite. Boundary is inspection metadata, never a sketch limit.
final class ResolvedPlanarSupport {
  ResolvedPlanarSupport({required this.frame, Face? boundary})
    : _boundary = boundary == null
          ? null
          : TopologyCopy().copy(boundary) as Face;
  final PlanarFrame frame;
  final Face? _boundary;
  Face? get boundary =>
      _boundary == null ? null : TopologyCopy().copy(_boundary) as Face;
}
