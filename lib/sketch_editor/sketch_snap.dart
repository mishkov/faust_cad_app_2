import 'package:vector_math/vector_math_64.dart' show Vector2;

final class SketchSnap {
  SketchSnap(Vector2 position, this.label) : _position = position.clone();
  final Vector2 _position;
  Vector2 get position => _position.clone();
  final String label;
}
