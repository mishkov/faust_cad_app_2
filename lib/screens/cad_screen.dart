import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
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
  double _previousGestureScale = 1.0;

  var _cameraPosition = CameraConfig(
    position: Vector3(0, -50, 100),
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
                        yaw: _cameraPosition.yaw - event.panDelta.dx * 0.005,
                        pitch:
                            _cameraPosition.pitch - event.panDelta.dy * 0.005,
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
                      Cube(centerPosition: Vector3(15, 16, 19), size: 20),
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
