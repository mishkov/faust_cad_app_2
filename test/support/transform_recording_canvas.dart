import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

// Flutter's recording canvas records getTransform without returning a matrix.
// Supply an actual transform for renderer coverage tests.
class TransformRecordingCanvas extends TestRecordingCanvas {
  @override
  Float64List getTransform() => Matrix4.identity().storage;
}
