// Shared by authored parameters and generic non-topological outputs.
Object? freezeValue(Object? value) => switch (value) {
  null || String() || bool() || int() => value,
  double() when value.isFinite => value,
  List() => List<Object?>.unmodifiable(value.map(freezeValue)),
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k, freezeValue(v))),
  ),
  _ => throw ArgumentError(
    'Values must be finite scalar, list, or string-keyed map values',
  ),
};
