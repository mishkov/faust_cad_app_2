import 'dart:math' as math;

/// Builds a line-segment demonstration profile, not an involute gear feature.
Map<String, Object?> demoGearSketch(String id, double centerX, double phase) {
  const teeth = 24;
  final points = <Map<String, Object?>>[];
  for (var tooth = 0; tooth < teeth; tooth++) {
    for (final (offset, radius) in [
      (-0.34, 13.5),
      (-0.12, 16.0),
      (0.12, 16.0),
      (0.34, 13.5),
    ]) {
      final angle = phase + (tooth + offset) * 2 * math.pi / teeth;
      points.add({
        'id': 'p${points.length}',
        'x': centerX + radius * math.cos(angle),
        'y': radius * math.sin(angle),
      });
    }
  }
  return {
    'featureId': id,
    'name': '$id outline',
    'plane': 'xy',
    'points': [
      ...points,
      {'id': 'bore-center', 'x': centerX, 'y': 0},
    ],
    'segments': [
      for (var i = 0; i < points.length; i++)
        {'id': 'edge$i', 'start': 'p$i', 'end': 'p${(i + 1) % points.length}'},
    ],
    'circles': [
      {'id': 'bore', 'center': 'bore-center', 'radius': 2.5},
    ],
  };
}
