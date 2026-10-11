import 'package:equatable/equatable.dart';

/// A caller-assigned identity unique across all entities in one sketch.
final class SketchEntityId extends Equatable {
  SketchEntityId(this.value) {
    if (value.isEmpty) {
      throw ArgumentError('Sketch entity ID must not be empty');
    }
  }

  /// The stable identity, independent of coordinates and collection order.
  final String value;

  @override
  List<Object> get props => [value];

  @override
  String toString() => value;
}
