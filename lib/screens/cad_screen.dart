import 'dart:math' as math;

import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/plane_surface.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/planar_support_resolution.dart';
import 'package:faust_cad_app_2/sketch/sketch_geometry.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_editor_controller.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../cad_scene/cad_primitivies/solid.dart';
import '../cad_scene/navigation/camera_side.dart';
import '../cad_scene/navigation/view_cube.dart';
import '../cad_scene/rendering/tessellation/scene_tessellator.dart';
import '../document/features/extrude_feature.dart';
import '../extrusion_editor/extrusion_editor_controller.dart';
import '../extrusion_editor/extrusion_workspace.dart';
import '../feature_history/feature_history_panel.dart';
import '../step_export/step_export_button.dart';

class CadScreen extends StatefulWidget {
  const new({super.key, this.controller});

  final DocumentController? controller;

  @override
  State<CadScreen> createState() => _CadScreenState();
}

class _CadScreenState extends State<CadScreen>
    with SingleTickerProviderStateMixin {
  static const _initialFocusDistance = 200.0;

  double _previousGestureScale = 1.0;

  late final _document =
      widget.controller ??
      DocumentController(
        evaluators: {
          CubeFeature.type: CubeFeature.evaluate,
          SketchFeature.type: SketchFeature.evaluate,
          ExtrudeFeature.type: ExtrudeFeature.evaluate,
        },
      );
  late var _evaluated = _document.evaluation.materializeGeometry();
  late final _editor = SketchEditorController(_document);
  late final _extrusionEditor = ExtrusionEditorController(_document);
  CameraConfig? _previousCamera;
  var _plane = PrincipalPlane.xy;
  OutputReference? _selectedReference;
  FeatureId? _selectedFeature;
  PlanarSupport? _inspectedSupport;
  var _selectionMode = ViewportSelectionMode.planarFace;

  final List<CadPrimitive> _geometry = [...GroundGrid(100, 100).build()];

  static final _initialCameraPosition = CameraConfig(
    position: Vertex(Vector3(0, -50, 100)),
    yaw: 0.0,
    pitch: -0.5,
    focalLength: 500.0,
    focusDistance: _initialFocusDistance,
  );

  late CameraConfig _cameraPosition = _initialCameraPosition;
  late CameraConfig _cameraStart;
  late CameraConfig _cameraTarget;
  late final AnimationController _cameraAnimation;

  @override
  void initState() {
    super.initState();
    _document.addListener(_documentChanged);
    _editor.addListener(_editorChanged);
    _extrusionEditor.addListener(_extrusionChanged);
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..addListener(_animateCamera);
  }

  void _resetCamera() {
    _animateTo(_initialCameraPosition);
  }

  void _animateTo(CameraConfig target) {
    _cameraStart = _cameraPosition;
    _cameraTarget = target;
    _cameraAnimation.forward(from: 0);
  }

  void _selectSide(CameraSide side) {
    final scene = SceneTessellator().buildGeometry([
      ..._geometry,
      ..._evaluated.geometry,
    ]);
    final points = <Vector3>[
      for (final edge in scene.edges) ...edge.points,
      for (final face in scene.faces)
        for (final triangle in face.triangles) ...triangle.points,
    ];
    for (final output in _document.evaluation.dataOutputs) {
      final data = output.data;
      if (data is! SketchGeometry) continue;
      final frame = data.frame;
      for (final point in data.solved.points.values) {
        points.add(frame.localToWorld(point.position));
      }
      for (final circle in data.solved.circles.values) {
        final center = frame.localToWorld(
          data.solved.points[circle.centerPointId]!.position,
        );
        final extent = Vector3.zero();
        for (var i = 0; i < 3; i++) {
          extent[i] =
              circle.radius *
              math.sqrt(
                frame.xAxis[i] * frame.xAxis[i] +
                    frame.yAxis[i] * frame.yAxis[i],
              );
        }
        points.addAll([center - extent, center + extent]);
      }
    }
    final target = side.cameraFor(_cameraPosition, points);
    // Take the shortest yaw path, including when the user has made full turns.
    final turn =
        (target.yaw - _cameraPosition.yaw + math.pi) % (2 * math.pi) - math.pi;
    _animateTo(target.copyWith(yaw: _cameraPosition.yaw + turn));
  }

  void _animateCamera() {
    final t = Curves.easeInOut.transform(_cameraAnimation.value);
    double interpolate(double start, double end) => start + (end - start) * t;

    setState(() {
      _cameraPosition = _cameraAnimation.isCompleted
          ? _cameraTarget
          : CameraConfig(
              isOrthographic: _cameraStart.isOrthographic,
              position: Vertex(
                _cameraStart.position.vector +
                    (_cameraTarget.position.vector -
                            _cameraStart.position.vector) *
                        t,
              ),
              yaw: interpolate(_cameraStart.yaw, _cameraTarget.yaw),
              pitch: interpolate(_cameraStart.pitch, _cameraTarget.pitch),
              focalLength: interpolate(
                _cameraStart.focalLength,
                _cameraTarget.focalLength,
              ),
              focusDistance: interpolate(
                _cameraStart.focusDistance,
                _cameraTarget.focusDistance,
              ),
            );
    });
  }

  @override
  void dispose() {
    _document.removeListener(_documentChanged);
    _editor.removeListener(_editorChanged);
    _editor.dispose();
    _extrusionEditor.removeListener(_extrusionChanged);
    _extrusionEditor.dispose();
    if (widget.controller == null) _document.dispose();
    _cameraAnimation.dispose();
    super.dispose();
  }

  void _select(ViewportHit? hit) {
    setState(() {
      _selectedReference = _selectionMode == ViewportSelectionMode.body
          ? hit?.bodyReference
          : hit?.faceReference;
      _selectedFeature = _selectedReference?.featureId;
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

  void _documentChanged() {
    _evaluated = _document.evaluation.materializeGeometry();
    if (_selectedReference != null &&
        !{
          ..._evaluated.faces.values,
          ..._evaluated.bodies.values,
        }.contains(_selectedReference)) {
      _selectedReference = null;
      _inspectedSupport = null;
    }
    if (!_document.features.any((f) => f.id == _selectedFeature)) {
      _selectedFeature = null;
    }
    if (mounted) setState(() {});
  }

  void _selectFeature(FeatureId id) {
    setState(() {
      _selectedFeature = id;
      _selectedReference = _evaluated.bodies.values
          .where((reference) => reference.featureId == id)
          .firstOrNull;
      _inspectedSupport = null;
    });
  }

  void _editorChanged() {
    if (_editor.activeId == null && _previousCamera != null) {
      _cameraPosition = _previousCamera!;
      _previousCamera = null;
    }
    if (mounted) setState(() {});
  }

  void _enterSketch({FeatureId? id, PlanarSupport? support}) {
    _cameraAnimation.stop();
    final previous = _previousCamera ?? _cameraPosition;
    if (id != null) {
      _editor.open(id);
    } else {
      _editor.create(support!);
    }
    _previousCamera = previous;
    final frame = _editor.support?.frame;
    if (frame != null) {
      final direction = -frame.normal;
      _cameraPosition = CameraConfig(
        position: Vertex(frame.origin - direction * 200),
        yaw: math.atan2(-direction.x, direction.y),
        pitch: math.asin(direction.z.clamp(-1.0, 1.0)),
        focalLength: 500,
        focusDistance: 200,
      );
    }
    setState(() {});
  }

  void _extrusionChanged() {
    if (mounted) setState(() {});
  }

  void _enterExtrusion(
    FeatureId sketchId, {
    Iterable<String> regions = const [],
  }) {
    _editor.close();
    _extrusionEditor.create(sketchId, regionIds: regions);
  }

  void _extrudeSketch() {
    final id = _editor.activeId!;
    final selected = _editor.selectedRegionIds.toList();
    _enterExtrusion(id, regions: selected);
  }

  void _leaveSketch() {
    _editor.close();
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sketches'),
            DropdownButton<PrincipalPlane>(
              value: _plane,
              items: [
                for (final p in PrincipalPlane.values)
                  DropdownMenuItem(value: p, child: Text(p.name.toUpperCase())),
              ],
              onChanged: (p) => setState(() => _plane = p!),
            ),
            FilledButton(
              key: const Key('new-sketch'),
              onPressed: () =>
                  _enterSketch(support: PlanarSupport.principal(_plane)),
              child: const Text('New sketch'),
            ),
            OutlinedButton(
              key: const Key('sketch-on-face'),
              onPressed: _inspectedSupport == null
                  ? null
                  : () => _enterSketch(support: _inspectedSupport),
              child: const Text('Sketch on selected face'),
            ),
            const Divider(),
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
    if (_extrusionEditor.activeId != null) {
      return Scaffold(body: ExtrusionWorkspace(editor: _extrusionEditor));
    }
    if (_editor.activeId != null) {
      return Scaffold(
        body: SketchWorkspace(
          editor: _editor,
          onClose: _leaveSketch,
          onExtrude: _extrudeSketch,
        ),
      );
    }
    final evaluated = _evaluated;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            _resetCamera,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
            _editor.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _editor.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _editor.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _editor.redo,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Center(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          const Text('Model edits'),
                          IconButton(
                            tooltip: 'Undo',
                            onPressed: _document.canUndo ? _editor.undo : null,
                            icon: const Icon(Icons.undo),
                          ),
                          IconButton(
                            tooltip: 'Redo',
                            onPressed: _document.canRedo ? _editor.redo : null,
                            icon: const Icon(Icons.redo),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: StepExportButton(
                          solids: evaluated.geometry
                              .whereType<Solid>()
                              .toList(),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: FeatureHistoryPanel(
                          document: _document,
                          selectedId: _selectedFeature,
                          onSelected: _selectFeature,
                          onOpenSketch: (id) => _enterSketch(id: id),
                          onEditExtrusion: _extrusionEditor.open,
                          onExtrudeSketch: _enterExtrusion,
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(flex: 2, child: _inspectionPanel()),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerPanZoomStart: (_) {
                        _cameraAnimation.stop();
                        _previousGestureScale = 1.0;
                      },
                      onPointerPanZoomUpdate: (event) {
                        _cameraAnimation.stop();
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
                            isOrthographic: orientationChanged
                                ? false
                                : _cameraPosition.isOrthographic,
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CadScene(
                            cameraConfig: _cameraPosition,
                            sketches: [
                              for (final output
                                  in _document.evaluation.dataOutputs)
                                if (output.data is SketchGeometry)
                                  output.data as SketchGeometry,
                            ],
                            renderMode: CadRenderMode.shaded,
                            geometry: _geometry,
                            evaluatedGeometry: evaluated,
                            selectionMode: _selectionMode,
                            onSelected: _select,
                            selectedReference: _selectedReference,
                            geometryRevision: _document.evaluation.revision,
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: ViewCube(
                              camera: _cameraPosition,
                              onSelected: _selectSide,
                            ),
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
