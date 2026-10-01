import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: CadScreen());
  }
}

class CadScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<CadScreen> createState() => _CadScreenState();
}

class _CadScreenState extends State<CadScreen> {
  double _previousGestureScale = 1.0;

  var _cameraPosition = CameraConfig(
    position: Point3d(0, -50, 100),
    yaw: 0.0,
    pitch: -0.5,
    focalLength: 500.0,
    focusDistance: 200.0,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: EdgeInsets.all(8.0), child: Text('Hello World!')),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerPanZoomStart: (_) => _previousGestureScale = 1.0,
                  onPointerPanZoomUpdate: (event) {
                    final scaleFactor = event.scale / _previousGestureScale;
                    if (event.scale.isFinite && event.scale > 0) {
                      _previousGestureScale = event.scale;
                    }

                    setState(() {
                      final rotatedCamera = _cameraPosition.copyWith(
                        yaw: _cameraPosition.yaw + event.panDelta.dx * 0.005,
                        pitch:
                            _cameraPosition.pitch + event.panDelta.dy * 0.005,
                      );
                      _cameraPosition = rotatedCamera.zoomTowardCursor(
                        cursor: event.localPosition,
                        viewport: constraints.biggest,
                        scaleFactor: scaleFactor,
                      );
                    });
                  },
                  onPointerPanZoomEnd: (_) => _previousGestureScale = 1.0,
                  child: CadScene(
                    cameraConfig: _cameraPosition,
                    cadObjects: [GroundGrid(100, 100)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CadScene extends StatefulWidget {
  const new({super.key, required this.cameraConfig, required this.cadObjects});

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

  @override
  State<CadScene> createState() => _CadSceneState();
}

class _CadSceneState extends State<CadScene> {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CadScenePainter(
        cameraConfig: widget.cameraConfig,
        cadObjects: widget.cadObjects,
      ),
    );
  }
}

class CadScenePainter extends CustomPainter {
  const new({required this.cameraConfig, required this.cadObjects});

  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;

  @override
  void paint(Canvas canvas, Size size) {
    for (final cadObject in cadObjects) {
      final primitives = cadObject.build();

      for (final primitive in primitives) {
        switch (primitive) {
          case Line3d(begin: Point3d begin, end: Point3d end):
            final beginPoint = _project(begin, cameraConfig, screen: size);
            final endPoint = _project(end, cameraConfig, screen: size);

            if (beginPoint == null || endPoint == null) {
              break;
            }

            canvas.drawLine(
              Offset(beginPoint.x, beginPoint.y),
              Offset(endPoint.x, endPoint.y),
              Paint()
                ..color = Colors.red
                ..strokeWidth = 1,
            );
        }
      }
    }
  }

  ({double x, double y})? _project(
    Point3d point,
    CameraConfig camera, {
    required Size screen,
  }) {
    final p = _toCameraSpace(point, camera);

    final befindCamera = p.y <= 0;
    if (befindCamera) return null;

    return (
      x: screen.width / 2 + p.x / p.y * camera.focalLength,
      y: screen.height / 2 - p.z / p.y * camera.focalLength,
    );
  }

  Point3d _toCameraSpace(Point3d point, CameraConfig camera) {
    var p = point - camera.position;

    // Inverse camera yaw: rotate around Z
    final cy = math.cos(-camera.yaw);
    final sy = math.sin(-camera.yaw);

    final x1 = p.x * cy - p.y * sy;
    final y1 = p.x * sy + p.y * cy;
    final z1 = p.z;

    // Inverse camera pitch: rotate around X
    final cp = math.cos(-camera.pitch);
    final sp = math.sin(-camera.pitch);

    final y2 = y1 * cp - z1 * sp;
    final z2 = y1 * sp + z1 * cp;

    return Point3d(x1, y2, z2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}

class CameraConfig with Equatable {
  final Point3d position;
  final double yaw;
  final double pitch;
  final double focalLength;

  /// Camera-space depth of the point used for cursor zoom.
  final double focusDistance;

  new({
    required this.position,
    required this.yaw,
    required this.pitch,
    required this.focalLength,
    required this.focusDistance,
  }) : assert(focalLength.isFinite && focalLength > 0),
       assert(focusDistance.isFinite && focusDistance > 0);

  @override
  List<Object?> get props => [position, yaw, pitch, focalLength, focusDistance];

  CameraConfig copyWith({
    Point3d? position,
    double? yaw,
    double? pitch,
    double? focalLength,
    double? focusDistance,
  }) {
    return CameraConfig(
      position: position ?? this.position,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      focalLength: focalLength ?? this.focalLength,
      focusDistance: focusDistance ?? this.focusDistance,
    );
  }

  CameraConfig zoomTowardCursor({
    required Offset cursor,
    required Size viewport,
    required double scaleFactor,
  }) {
    if (!scaleFactor.isFinite ||
        scaleFactor <= 0 ||
        scaleFactor == 1 ||
        viewport.isEmpty) {
      return this;
    }

    // Reverse the painter's perspective projection to get the cursor ray.
    final rayX = (cursor.dx - viewport.width / 2) / focalLength;
    final rayZ = (viewport.height / 2 - cursor.dy) / focalLength;
    final cp = math.cos(pitch);
    final sp = math.sin(pitch);
    final pitchedY = cp - rayZ * sp;
    final directionZ = sp + rayZ * cp;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final directionX = rayX * cy - pitchedY * sy;
    final directionY = rayX * sy + pitchedY * cy;

    // A screen position defines a ray, so use the camera's focus depth to
    // choose a point on that ray, regardless of which way it points.
    final distance = focusDistance;
    // Pinching out increases scale and moves the camera along the cursor ray.
    final factor = 1 / scaleFactor.clamp(0.2, 5.0);
    final step = distance * (1 - factor);
    return copyWith(
      position: Point3d(
        position.x + directionX * step,
        position.y + directionY * step,
        position.z + directionZ * step,
      ),
      focusDistance: distance * factor,
    );
  }
}

abstract class CadObject {
  List<CadPrimitive> build();
}

class GroundGrid extends CadObject {
  final double width;
  final double length;

  GroundGrid([this.width = 100, this.length = 100]);

  @override
  List<CadPrimitive> build() {
    return [
      for (int i = 0; i < 11; i++)
        Line3d(
          Point3d(i / 10 * width, 0, 0),
          Point3d(i / 10 * width, length, 0),
        ),
      for (int i = 0; i < 11; i++)
        Line3d(
          Point3d(0, i / 10 * length, 0),
          Point3d(width, i / 10 * length, 0),
        ),
    ];
  }
}

class Line3d extends CadPrimitive {
  final Point3d begin, end;

  new(this.begin, this.end);
}

class Point3d extends CadPrimitive {
  final double x, y, z;

  new(this.x, this.y, this.z);

  Point3d operator -(Point3d other) =>
      Point3d(x - other.x, y - other.y, z - other.z);
}

abstract class CadPrimitive {}
