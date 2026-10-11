import '../../sketch/sketch_definition.dart';
import '../../sketch/sketch_geometry.dart';
import '../../sketch/sketch_drag_target.dart';
import '../../sketch/sketch_solver.dart';
import '../../sketch/sketch_solver_settings.dart';
import '../../sketch/sketch_solve_result.dart';
import '../document_controller.dart';
import '../feature_evaluation_failure.dart';
import '../feature_result.dart';
import '../feature_definition.dart';
import '../feature_evaluation_context.dart';
import '../feature_id.dart';
import '../feature_output.dart';

/// Solves and publishes a valid sketch as independent non-topological geometry.
final class SketchFeature {
  static const type = 'sketch';
  static const outputKey = 'sketch';
  static const parameterKey = 'sketch';

  /// Creates a document-owned value definition, including its support dependency.
  static FeatureDefinition definition({
    required FeatureId id,
    required SketchDefinition sketch,
  }) => FeatureDefinition(
    id: id,
    type: type,
    support: sketch.support,
    parameters: {parameterKey: sketch.toParameters()},
  );

  /// Reads the current authored values from a feature definition.
  static SketchDefinition readDefinition(FeatureDefinition definition) {
    if (definition.type != type || definition.support == null) {
      throw ArgumentError('Sketch requires a sketch type and planar support');
    }
    return SketchDefinition.fromParameters(
      support: definition.support!,
      parameters: definition.parameters[parameterKey],
    );
  }

  /// Places validated local entities on the support resolved by feature history.
  static List<FeatureOutput> evaluate(
    FeatureDefinition definition,
    FeatureEvaluationContext context,
  ) {
    final sketch = readDefinition(definition);
    final support = context.support;
    if (support == null) throw StateError('Sketch support is unresolved');
    final solution = const SketchSolver().solve(sketch);
    if (!solution.isValid) {
      throw FeatureEvaluationFailure(
        issue: FeatureIssue.constraintSolveFailed,
        message: 'Sketch solve ${solution.status.name}',
        diagnostics: {'sketchSolve': solution.toDiagnostics()},
      );
    }
    return [
      FeatureOutput.sketch(
        key: outputKey,
        data: SketchGeometry(
          definition: sketch,
          frame: support.frame,
          solution: solution,
        ),
      ),
    ];
  }

  /// Applies a constrained drag preview through ordinary document edits.
  ///
  /// An active controller transaction coalesces previews into one undo entry.
  /// Failed solves return diagnostics and leave authored data unchanged. Targets
  /// remain temporary; persistent relations and IDs survive all accepted drags.
  static SketchSolveResult drag(
    DocumentController controller,
    FeatureId id,
    Iterable<SketchDragTarget> targets, {
    SketchSolverSettings? settings,
    String label = 'Drag sketch',
  }) {
    final feature = controller.features.firstWhere(
      (f) => f.id == id,
      orElse: () => throw ArgumentError('Missing sketch feature: $id'),
    );
    final authored = readDefinition(feature);
    final result = const SketchSolver().solve(
      authored,
      settings: settings,
      dragTargets: targets,
    );
    if (result.isValid) {
      final solved = result.geometry!;
      final updated = authored.copyWith(
        points: solved.points.values,
        circles: solved.circles.values,
      );
      controller.updateParameters(id, {
        parameterKey: updated.toParameters(),
      }, label: label);
    }
    return result;
  }
}
