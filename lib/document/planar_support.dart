import 'package:equatable/equatable.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_scene/geometry/src/vector_validation.dart';
import 'output_reference.dart';

enum PrincipalPlane { xy, xz, yz }

// Value data only: survives undo/redo and never retains evaluated topology.
final class PlanarSupport extends Equatable {
  const PlanarSupport.principal(PrincipalPlane plane)
    : principalPlane = plane,
      reference = null,
      _direction = null;

  factory PlanarSupport.face({
    required OutputReference reference,
    required Vector3 preferredDirection,
  }) {
    if (reference.kind == OutputKind.body) {
      throw ArgumentError('A support requires a face reference');
    }
    final direction = normalizedVector3(
      preferredDirection,
      'preferredDirection',
    );
    return PlanarSupport._(reference, (direction.x, direction.y, direction.z));
  }

  const PlanarSupport._(this.reference, this._direction)
    : principalPlane = null;
  final PrincipalPlane? principalPlane;
  final OutputReference? reference;
  final (double, double, double)? _direction;

  // This fixed model-space direction is projected on every evaluation. It is
  // deliberate, never switched to another world axis when nearly normal.
  Vector3? get preferredDirection => _direction == null
      ? null
      : Vector3(_direction.$1, _direction.$2, _direction.$3);

  @override
  List<Object?> get props => [principalPlane, reference, _direction];
}
