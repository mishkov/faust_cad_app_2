import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../camera_config.dart';
import '../cad_primitivies/vertex.dart';
import '../rendering/camera_projection.dart';

// Z is up. Front is the negative Y side, matching the model's face names.
enum CameraSide {
  top('Top', 0, -math.pi / 2),
  front('Front', 0, 0),
  left('Left', -math.pi / 2, 0),
  right('Right', math.pi / 2, 0),
  back('Back', math.pi, 0),
  bottom('Bottom', 0, math.pi / 2);

  const CameraSide(this.label, this.yaw, this.pitch);
  final String label;
  final double yaw;
  final double pitch;

  CameraProjection get orientation => CameraProjection(
    CameraConfig(
      position: Vertex(Vector3.zero()),
      yaw: yaw,
      pitch: pitch,
      focalLength: 1,
      focusDistance: 1,
    ),
  );

  Vector3 get outward => -orientation.fromCameraDirection(Vector3(0, 1, 0));

  CameraConfig cameraFor(CameraConfig current, Iterable<Vector3> points) {
    final low = Vector3.all(double.infinity);
    final high = Vector3.all(double.negativeInfinity);
    for (final point in points) {
      for (var i = 0; i < 3; i++) {
        low[i] = math.min(low[i], point[i]);
        high[i] = math.max(high[i], point[i]);
      }
    }
    final center = low.x.isFinite ? (low + high) * 0.5 : Vector3.zero();
    final extent = low.x.isFinite ? (high - low) * 0.5 : Vector3.zero();
    final normal = outward;
    final halfDepth =
        normal.x.abs() * extent.x +
        normal.y.abs() * extent.y +
        normal.z.abs() * extent.z;
    // Move beyond the entire scene without changing its orthographic scale.
    final margin = math.max(1.0, extent.length * 0.01);
    final distance = math.max(current.focusDistance, halfDepth + margin);
    return current.copyWith(
      position: Vertex(center + normal * distance),
      yaw: yaw,
      pitch: pitch,
      isOrthographic: true,
    );
  }
}
