import 'package:faust_cad_app_2/cad_scene/cad_curves/cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/circular_trim.dart';
import 'package:faust_cad_app_2/cad_scene/cad_curves/linear_cad_curve.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/src/vector_validation.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

/// A bounded, directed topological use of underlying [curve] geometry.
///
/// Circular edges require an explicit [trim] consistent with the supplied shared
/// vertices. Linear edges retain their endpoint-defined segment convention.
class Edge extends CadPrimitive {
  final Vertex begin, end;
  final CadCurve curve;
  final CircularTrim? trim;

  Edge(this.begin, this.end, {required this.curve, this.trim}) {
    if (curve is CircularCadCurve) {
      if (trim == null || !hasValidCircularEndpoints) {
        throw ArgumentError(
          'Circular edges need a trim and consistent distinct endpoints',
        );
      }
    } else if (trim != null) {
      throw ArgumentError('Circular trims require a CircularCadCurve');
    }
  }

  /// Checks endpoint agreement using the circle frame's model distance policy.
  ///
  /// Rechecked by shell validation because vertex positions remain mutable.
  bool get hasValidCircularEndpoints {
    final circle = curve;
    final interval = trim;
    if (circle is! CircularCadCurve || interval == null) return false;
    if (identical(begin, end) || begin.vector == end.vector) return false;
    for (final endpoint in [
      (begin.vector, interval.startAngle),
      (end.vector, interval.endAngle),
    ]) {
      final delta = endpoint.$1 - circle.evaluate(endpoint.$2);
      final distance = delta.length;
      if (!distance.isFinite || distance > circle.frame.tolerance.distance) {
        return false;
      }
    }
    return true;
  }

  /// Evaluates traversal at t in [0, 1], from [begin] to [end].
  ///
  /// Circular evaluation uses the analytic trim, never an endpoint chord.
  /// Unknown curve types throw [UnsupportedError].
  Vector3 evaluate(double parameter) {
    _requireParameter(parameter);
    final geometry = curve;
    if (geometry is CircularCadCurve) {
      return geometry.evaluate(trim!.angleAt(parameter));
    }
    if (geometry is LinearCadCurve) {
      return finiteVector3Result(
        begin.vector * (1 - parameter) + end.vector * parameter,
      );
    }
    throw UnsupportedError('Evaluation is not defined for this curve type');
  }

  /// The derivative with respect to normalized traversal t, not a unit vector.
  ///
  /// Circular tangents include the signed sweep, so reversal negates traversal.
  Vector3 tangent(double parameter) {
    _requireParameter(parameter);
    final geometry = curve;
    if (geometry is CircularCadCurve) {
      return finiteVector3Result(
        geometry.tangent(trim!.angleAt(parameter)) * trim!.sweepAngle,
      );
    }
    if (geometry is LinearCadCurve) {
      return finiteVector3Result(end.vector - begin.vector);
    }
    throw UnsupportedError('Tangents are not defined for this curve type');
  }

  /// Reuses the curve and endpoint instances while reversing the bounded use.
  Edge reversed() => Edge(end, begin, curve: curve, trim: trim?.reversed());

  /// Whether two uses reference the same bounded boundary, ignoring traversal.
  ///
  /// Vertex identity is mandatory. Linear segments match by endpoints; other
  /// geometry must share a curve instance. Circles additionally compare trims,
  /// using the frame's angular threshold as a radian roundoff threshold.
  bool hasSameBoundary(Edge other) {
    final sameDirection =
        identical(begin, other.begin) && identical(end, other.end);
    final oppositeDirection =
        identical(begin, other.end) && identical(end, other.begin);
    if (!sameDirection && !oppositeDirection) return false;
    if (curve is LinearCadCurve && other.curve is LinearCadCurve) return true;
    if (!identical(curve, other.curve)) return false;
    final geometry = curve;
    if (geometry is CircularCadCurve) {
      return trim!.matches(
        sameDirection ? other.trim! : other.trim!.reversed(),
        angularTolerance: geometry.frame.tolerance.angular,
      );
    }
    return true;
  }

  void _requireParameter(double parameter) {
    if (!parameter.isFinite || parameter < 0 || parameter > 1) {
      throw ArgumentError.value(parameter, 'parameter', 'Must be in [0, 1]');
    }
  }
}
