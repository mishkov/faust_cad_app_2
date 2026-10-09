import 'package:equatable/equatable.dart';

final class FeatureId extends Equatable {
  FeatureId(this.value) {
    if (value.isEmpty) throw ArgumentError('Feature ID must not be empty');
  }

  final String value;
  @override
  List<Object> get props => [value];
  @override
  String toString() => value;
}
