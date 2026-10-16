import '../cad_scene/cad_primitivies/solid.dart';
import 'src/step_writer.dart';

/// Exports analytic solid geometry as STEP AP214 B-reps in millimeters.
final class StepExporter {
  const StepExporter();

  /// Serializes [solids], preserving shared topology and analytic geometry.
  ///
  /// One model length unit becomes one millimeter. Empty input, invalidated
  /// manifold topology, and nonfinite coordinates throw. Unsupported curve or
  /// surface types throw [UnsupportedError] without returning a partial file.
  /// Geometric validity and material-side orientation remain the caller's
  /// responsibility, as they do for [Solid].
  String exportSolids(Iterable<Solid> solids, {DateTime? timestamp}) {
    final bodies = solids.toList();
    if (bodies.isEmpty) {
      throw StateError('There are no solid bodies to export.');
    }
    return StepWriter().write(bodies, timestamp ?? DateTime.now());
  }
}
