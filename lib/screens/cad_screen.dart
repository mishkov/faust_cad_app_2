import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class CadScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<CadScreen> createState() => _CadScreenState();
}

class _CadScreenState extends State<CadScreen> {
  static const _initialFocusDistance = 200.0;

  double _previousGestureScale = 1.0;

  var _cameraPosition = CameraConfig(
    position: Vertex(Vector3(0, -50, 100)),
    yaw: 0.0,
    pitch: -0.5,
    focalLength: 500.0,
    focusDistance: _initialFocusDistance,
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
                      final yaw =
                          _cameraPosition.yaw - event.panDelta.dx * 0.005;
                      final pitch =
                          _cameraPosition.pitch - event.panDelta.dy * 0.005;
                      final orientationChanged =
                          yaw != _cameraPosition.yaw ||
                          pitch != _cameraPosition.pitch;
                      final rotatedCamera = _cameraPosition.copyWith(
                        yaw: yaw,
                        pitch: pitch,
                        // Rotation starts looking along a different ray, so
                        // discard the depth accumulated by earlier zooms.
                        focusDistance: orientationChanged
                            ? _initialFocusDistance
                            : _cameraPosition.focusDistance,
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
                    cadObjects: [
                      GroundGrid(100, 100),
                      Cube(
                        centerPosition: Vertex(Vector3(15, 16, 19)),
                        size: 20,
                      ),
                    ],
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
