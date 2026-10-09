import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/planar_support_resolution.dart';
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

  final _document = CadDocument(
    evaluators: {CubeFeature.type: CubeFeature.evaluate},
    features: [
      FeatureDefinition(
        id: FeatureId('cube-a'),
        type: CubeFeature.type,
        parameters: {'x': 15, 'y': 16, 'z': 19, 'size': 20},
      ),
      FeatureDefinition(
        id: FeatureId('cube-b'),
        type: CubeFeature.type,
        parameters: {'x': 40, 'y': 16, 'z': 15, 'size': 30},
      ),
    ],
  );
  late final _evaluated = _document.evaluation.materializeGeometry();
  OutputReference? _selectedReference;
  PlanarSupport? _inspectedSupport;
  var _selectionMode = ViewportSelectionMode.planarFace;

  final List<CadPrimitive> _geometry = [
    ...GroundGrid(100, 100).build(),
    ...Cylinder(
      frame: PlanarFrame.xy(origin: Vector3(60, 60, 0)),
      radius: 8,
      height: 15,
    ).build(),
  ];

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

  void _select(ViewportHit? hit) {
    setState(() {
      _selectedReference = _selectionMode == ViewportSelectionMode.body
          ? hit?.bodyReference
          : hit?.faceReference;
      _inspectedSupport = null;
      if (_selectionMode == ViewportSelectionMode.planarFace &&
          hit?.faceReference != null) {
        final normal = (hit!.face.surface as PlaneSurface).normal;
        _inspectedSupport = PlanarSupport.face(
          reference: hit.faceReference!,
          preferredDirection: normal.x.abs() < 0.9
              ? Vector3(1, 0, 0)
              : Vector3(0, 1, 0),
        );
      }
    });
  }

  Widget _inspectionPanel() {
    final resolution = _inspectedSupport == null
        ? null
        : PlanarSupportResolution.resolve(
            _inspectedSupport!,
            _document.evaluation,
          );
    final frame = resolution?.support?.frame;
    String vector(Vector3 v) =>
        '(${v.x.toStringAsFixed(3)}, ${v.y.toStringAsFixed(3)}, ${v.z.toStringAsFixed(3)})';
    return SizedBox(
      width: 240,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Viewport selection'),
            DropdownButton<ViewportSelectionMode>(
              value: _selectionMode,
              items: const [
                DropdownMenuItem(
                  value: ViewportSelectionMode.planarFace,
                  child: Text('Planar face'),
                ),
                DropdownMenuItem(
                  value: ViewportSelectionMode.body,
                  child: Text('Body'),
                ),
              ],
              onChanged: (mode) => setState(() {
                _selectionMode = mode!;
                _selectedReference = null;
                _inspectedSupport = null;
              }),
            ),
            const Text('Click a visible body face to inspect it.'),
            const SizedBox(height: 12),
            if (_selectedReference != null)
              Text(
                '${_selectedReference!.featureId}/${_selectedReference!.key}',
              ),
            if (resolution?.diagnostic != null) Text(resolution!.diagnostic!),
            if (frame != null) ...[
              const Text('Resolved plane'),
              Text('Origin: ${vector(frame.origin)}'),
              Text('X: ${vector(frame.xAxis)}'),
              Text('Y: ${vector(frame.yAxis)}'),
              Text('Normal: ${vector(frame.normal)}'),
              const SizedBox(height: 8),
              const Text(
                'Infinite support plane; the face boundary is only a trim.',
              ),
            ],
          ],
        ),
      ),
    );
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
                _inspectionPanel(),
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
                        geometry: _geometry,
                        evaluatedGeometry: _evaluated,
                        selectionMode: _selectionMode,
                        onSelected: _select,
                        selectedReference: _selectedReference,
                        geometryRevision: _document.evaluation.revision,
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
