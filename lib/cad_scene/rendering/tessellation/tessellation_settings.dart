import 'dart:math' as math;

/// View-independent rendering quality, in model units and radians.
class TessellationSettings {
  TessellationSettings({
    this.chordError = 0.01,
    this.maxAngle = math.pi / 12,
    this.maxSegmentsPerEdge = 512,
    this.maxTriangles = 20000,
  }) {
    if (!chordError.isFinite || chordError <= 0) {
      throw ArgumentError.value(chordError, 'chordError', 'Must be positive');
    }
    if (!maxAngle.isFinite || maxAngle <= 0 || maxAngle > math.pi / 2) {
      throw ArgumentError.value(maxAngle, 'maxAngle', 'Must be in (0, pi/2]');
    }
    if (maxSegmentsPerEdge < 1 || maxTriangles < 1) {
      throw ArgumentError('Tessellation budgets must be positive');
    }
  }

  static final defaults = TessellationSettings();
  final double chordError;
  final double maxAngle;
  final int maxSegmentsPerEdge;
  final int maxTriangles;

  /// Uses a numerically stable sagitta formula. Budgets never relax accuracy.
  int segments(double radius, double sweep) {
    final ratio = math.min(1.0, chordError / radius);
    final step = math.min(maxAngle, 4 * math.asin(math.sqrt(ratio / 2)));
    if (!step.isFinite ||
        step <= 0 ||
        sweep.abs() / step > maxSegmentsPerEdge) {
      throw StateError('Chord error requires more than maxSegmentsPerEdge');
    }
    return math.max(1, (sweep.abs() / step).ceil());
  }

  @override
  bool operator ==(Object other) =>
      other is TessellationSettings &&
      chordError == other.chordError &&
      maxAngle == other.maxAngle &&
      maxSegmentsPerEdge == other.maxSegmentsPerEdge &&
      maxTriangles == other.maxTriangles;

  @override
  int get hashCode =>
      Object.hash(chordError, maxAngle, maxSegmentsPerEdge, maxTriangles);
}
