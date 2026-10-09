import '../cad_scene/cad_curves/cad_curve.dart';
import '../cad_scene/cad_curves/circular_cad_curve.dart';
import '../cad_scene/cad_curves/linear_cad_curve.dart';
import '../cad_scene/cad_primitivies/cad_primitive.dart';
import '../cad_scene/cad_primitivies/edge.dart';
import '../cad_scene/cad_primitivies/face.dart';
import '../cad_scene/cad_primitivies/shell.dart';
import '../cad_scene/cad_primitivies/solid.dart';
import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/cad_primitivies/wire.dart';
import '../cad_scene/cad_surfaces/cad_surface.dart';
import '../cad_scene/cad_surfaces/cylinder_surface.dart';
import '../cad_scene/cad_surfaces/plane_surface.dart';

// Boundary copies preserve shared topology identities within each output.
// Unknown geometry fails explicitly rather than leaking an aliased mutable value.
final class TopologyCopy {
  final _primitives = Map<CadPrimitive, CadPrimitive>.identity();
  final _curves = Map<CadCurve, CadCurve>.identity();
  final _surfaces = Map<CadSurface, CadSurface>.identity();

  CadPrimitive copy(CadPrimitive source) => _primitives.putIfAbsent(
    source,
    () => switch (source) {
      Vertex(:final vector) => Vertex(vector.clone()),
      Edge() => Edge(
        copy(source.begin) as Vertex,
        copy(source.end) as Vertex,
        curve: _curve(source.curve),
        trim: source.trim,
      ),
      Wire(:final edges) => Wire([
        for (final edge in edges) copy(edge) as Edge,
      ]),
      Face() => Face(
        surface: _surface(source.surface),
        orientation: source.orientation,
        outerWire: copy(source.outerWire) as Wire,
        innerWires: [for (final wire in source.innerWires) copy(wire) as Wire],
      ),
      Shell(:final faces) => Shell(
        faces: [for (final face in faces) copy(face) as Face],
      ),
      Solid(:final shells) => Solid(
        shells: [for (final shell in shells) copy(shell) as Shell],
      ),
      _ => throw UnsupportedError(
        'Unsupported topology: ${source.runtimeType}',
      ),
    },
  );

  CadCurve _curve(CadCurve source) => _curves.putIfAbsent(
    source,
    () => switch (source) {
      LinearCadCurve() => const LinearCadCurve(),
      CircularCadCurve() => CircularCadCurve(
        frame: source.frame,
        radius: source.radius,
      ),
      _ => throw UnsupportedError('Unsupported curve: ${source.runtimeType}'),
    },
  );

  CadSurface _surface(CadSurface source) => _surfaces.putIfAbsent(
    source,
    () => switch (source) {
      PlaneSurface() => PlaneSurface(
        origin: source.origin,
        normal: source.normal,
      ),
      CylinderSurface() => CylinderSurface(
        frame: source.frame,
        radius: source.radius,
      ),
      _ => throw UnsupportedError('Unsupported surface: ${source.runtimeType}'),
    },
  );
}
