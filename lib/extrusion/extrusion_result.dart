import '../cad_scene/cad_primitivies/solid.dart';
import 'extruded_volume.dart';
import 'extrusion_diagnostic.dart';

/// An atomic extrusion result: failures never publish partial solids.
class ExtrusionResult {
  /// Freezes diagnostics and volumes, suppressing geometry on any error.
  ExtrusionResult({
    Iterable<ExtrudedVolume> volumes = const [],
    Iterable<ExtrusionDiagnostic> diagnostics = const [],
  }) : diagnostics = List.unmodifiable(diagnostics),
       volumes = List.unmodifiable(
         diagnostics.any((d) => d.isError) ? <ExtrudedVolume>[] : volumes,
       );

  /// The separate generated material volumes, empty on rejection.
  final List<ExtrudedVolume> volumes;

  /// The upstream warnings and operation rejection conditions.
  final List<ExtrusionDiagnostic> diagnostics;

  /// Whether the operation completed without an error diagnostic.
  bool get isValid => !diagnostics.any((d) => d.isError);

  /// The generated solids in the same order as [volumes].
  List<Solid> get solids => List.unmodifiable(volumes.map((v) => v.solid));
}
