import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../document/output_reference.dart';
import '../cad_primitivies/cad_primitive.dart';
import '../cad_primitivies/face.dart';
import '../cad_primitivies/edge.dart';

enum ViewportSelectionMode { body, planarFace, face, inspect }

final class ViewportHit {
  ViewportHit({
    required this.face,
    required this.owner,
    required Vector3 point,
    required this.depth,
    this.bodyReference,
    this.faceReference,
    this.edge,
  }) : _point = point.clone();
  final Face face;
  final Edge? edge;
  final CadPrimitive owner;
  final Vector3 _point;
  Vector3 get point => _point.clone();
  final double depth;
  final OutputReference? bodyReference;
  final OutputReference? faceReference;
}
