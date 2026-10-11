import 'package:equatable/equatable.dart';

/// A caller-assigned persistent constraint identity within one sketch.
final class SketchConstraintId extends Equatable {
  SketchConstraintId(this.value) {
    if (value.isEmpty) throw ArgumentError('Constraint ID must be nonempty');
  }
  final String value;
  @override
  List<Object> get props => [value];
  @override
  String toString() => value;
}
