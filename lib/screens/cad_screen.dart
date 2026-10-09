import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class CadScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<CadScreen> createState() => _CadScreenState();
}

class _CadScreenState extends State<CadScreen>
    with SingleTickerProviderStateMixin {
  static const _initialFocusDistance = 200.0;

  double _previousGestureScale = 1.0;

  static final _initialCameraPosition = CameraConfig(
    position: Vertex(Vector3(0, -50, 100)),
    yaw: 0.0,
    pitch: -0.5,
    focalLength: 500.0,
    focusDistance: _initialFocusDistance,
  );

  late CameraConfig _cameraPosition = _initialCameraPosition;
  late CameraConfig _resetStart;
  late final AnimationController _resetController;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_animateCameraReset);
  }

  void _resetCamera() {
    _resetStart = _cameraPosition;
    _resetController.forward(from: 0);
  }

  void _animateCameraReset() {
    final t = Curves.easeInOut.transform(_resetController.value);
    double interpolate(double start, double end) => start + (end - start) * t;

    setState(() {
      _cameraPosition = _resetController.isCompleted
          ? _initialCameraPosition
          : CameraConfig(
              position: Vertex(
                _resetStart.position.vector +
                    (_initialCameraPosition.position.vector -
                            _resetStart.position.vector) *
                        t,
              ),
              yaw: interpolate(_resetStart.yaw, _initialCameraPosition.yaw),
              pitch: interpolate(
                _resetStart.pitch,
                _initialCameraPosition.pitch,
              ),
              focalLength: interpolate(
                _resetStart.focalLength,
                _initialCameraPosition.focalLength,
              ),
              focusDistance: interpolate(
                _resetStart.focusDistance,
                _initialCameraPosition.focusDistance,
              ),
            );
    });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            _resetCamera,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Center(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Hello World!'),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerPanZoomStart: (_) {
                        _resetController.stop();
                        _previousGestureScale = 1.0;
                      },
                      onPointerPanZoomUpdate: (event) {
                        _resetController.stop();
                        final scaleFactor = event.scale / _previousGestureScale;
                        if (event.scale.isFinite && event.scale > 0) {
                          _previousGestureScale = event.scale;
                        }

                        setState(() {
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            _cameraPosition = _cameraPosition
                                .pan(event.panDelta)
                                .zoomTowardCursor(
                                  cursor: event.localPosition,
                                  viewport: constraints.biggest,
                                  scaleFactor: scaleFactor,
                                );
                            return;
                          }

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
                        renderMode: CadRenderMode.shaded,
                        cadObjects: [
                          GroundGrid(100, 100),
                          Cube(
                            centerPosition: Vertex(Vector3(15, 16, 19)),
                            size: 20,
                          ),
                          Cube(
                            centerPosition: Vertex(Vector3(40, 16, 15)),
                            size: 30,
                          ),
                          Cylinder(
                            frame: PlanarFrame.xy(origin: Vector3(60, 60, 0)),
                            radius: 8,
                            height: 15,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
