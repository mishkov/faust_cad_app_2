import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/cad_surfaces/plane_surface.dart';
import '../cad_scene/geometry/planar_frame.dart';
import 'evaluation_snapshot.dart';
import 'planar_support.dart';
import 'reference_resolution.dart';
import 'resolved_planar_support.dart';

final class PlanarSupportResolution {
  const PlanarSupportResolution._({this.support, this.diagnostic});
  final ResolvedPlanarSupport? support;
  final String? diagnostic;
  bool get isResolved => support != null;

  factory PlanarSupportResolution.resolve(
    PlanarSupport definition,
    EvaluationSnapshot snapshot,
  ) {
    final principal = definition.principalPlane;
    if (principal != null) {
      return PlanarSupportResolution._(
        support: ResolvedPlanarSupport(
          frame: switch (principal) {
            PrincipalPlane.xy => PlanarFrame.xy(),
            PrincipalPlane.xz => PlanarFrame.xz(),
            PrincipalPlane.yz => PlanarFrame.yz(),
          },
        ),
      );
    }
    final reference = definition.reference!;
    final resolved = snapshot.resolve(reference);
    if (resolved.status != ReferenceStatus.resolved) {
      return PlanarSupportResolution._(
        diagnostic:
            'Broken attachment: ${resolved.status.name} face '
            '${reference.featureId}/${reference.key}',
      );
    }
    final geometry = resolved.output!.geometry;
    if (geometry is! Face || geometry.surface is! PlaneSurface) {
      return const PlanarSupportResolution._(
        diagnostic: 'Broken attachment: referenced face is no longer planar',
      );
    }
    final plane = geometry.surface as PlaneSurface;
    try {
      final frame = PlanarFrame.fromPlane(
        plane: PlaneSurface(
          origin: plane.origin,
          normal: geometry.orientedNormal(plane.normal),
        ),
        preferredDirection: definition.preferredDirection!,
      );
      return PlanarSupportResolution._(
        support: ResolvedPlanarSupport(frame: frame, boundary: geometry),
      );
    } on ArgumentError catch (error) {
      return PlanarSupportResolution._(
        diagnostic: 'Broken attachment: in-plane axis is unresolved ($error)',
      );
    } on StateError catch (error) {
      return PlanarSupportResolution._(
        diagnostic: 'Broken attachment: invalid plane frame ($error)',
      );
    }
  }
}
