import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

/// Even-odd slab triangulation of simple loops with holes in surface coordinates.
/// The world positions at split boundaries interpolate the sampled chords,
/// retaining exactly the same boundary geometry on adjacent faces.
class TrimmedPolygon {
  static List<List<({Vector2 uv, Vector3 world})>> triangulate(
    List<List<({Vector2 uv, Vector3 world})>> loops, {
    required int budget,
  }) {
    final segments = [
      for (final loop in loops)
        for (var i = 0; i < loop.length; i++)
          (a: loop[i], b: loop[(i + 1) % loop.length]),
    ];
    final xs = loops.expand((loop) => loop.map((p) => p.uv.x)).toSet().toList()
      ..sort();
    final triangles = <List<({Vector2 uv, Vector3 world})>>[];
    for (var i = 0; i < xs.length - 1; i++) {
      final left = xs[i], right = xs[i + 1];
      if (right <= left) continue;
      final mid = left + (right - left) / 2;
      final crossings = segments
          .where(
            (s) =>
                (s.a.uv.x <= left && s.b.uv.x >= right) ||
                (s.b.uv.x <= left && s.a.uv.x >= right),
          )
          .toList();
      ({Vector2 uv, Vector3 world}) at(
        ({({Vector2 uv, Vector3 world}) a, ({Vector2 uv, Vector3 world}) b}) s,
        double x,
      ) {
        final t = ((x - s.a.uv.x) / (s.b.uv.x - s.a.uv.x)).clamp(0.0, 1.0);
        if (t == 0) return s.a;
        if (t == 1) return s.b;
        return (
          uv: s.a.uv * (1 - t) + s.b.uv * t,
          world: s.a.world * (1 - t) + s.b.world * t,
        );
      }

      crossings.sort((a, b) => at(a, mid).uv.y.compareTo(at(b, mid).uv.y));
      if (crossings.length.isOdd) throw StateError('Invalid trimming polygon');
      for (var j = 0; j < crossings.length; j += 2) {
        final a = at(crossings[j], left), b = at(crossings[j], right);
        final c = at(crossings[j + 1], right), d = at(crossings[j + 1], left);
        for (final tri in [
          [a, b, c],
          [a, c, d],
        ]) {
          final u = tri[1].uv - tri[0].uv, v = tri[2].uv - tri[0].uv;
          if ((u.x * v.y - u.y * v.x).abs() == 0) continue;
          triangles.add(tri);
          if (triangles.length > budget) {
            throw StateError('Face exceeds triangle budget');
          }
        }
      }
    }
    return triangles;
  }
}
