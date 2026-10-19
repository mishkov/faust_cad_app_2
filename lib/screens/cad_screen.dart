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
import 'package:faust_cad_app_2/sketch/sketch_geometry.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_editor_controller.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../cad_scene/cad_primitivies/solid.dart';
import '../cad_scene/navigation/camera_side.dart';
import '../cad_scene/navigation/view_cube.dart';
import '../cad_scene/rendering/camera_projection.dart';
import '../cad_scene/rendering/tessellation/scene_tessellator.dart';
import '../cad_scene/selection/selection_badge.dart';
import '../cad_scene/selection/selection_measurement.dart';
import '../document/feature_result.dart';
import '../document/features/extrude_feature.dart';
import '../extrusion_editor/extrusion_editor_controller.dart';
import '../extrusion_editor/extrusion_workspace.dart';
import '../feature_history/feature_history_panel.dart';
import '../sketch_editor/sketch_view.dart';
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
  bool _selectingSketchPlane = false;
  bool _enteringSketch = false;
  OutputReference? _selectedReference;
  FeatureId? _selectedFeature;
  ViewportHit? _selectedHit;

  final List<CadPrimitive> _geometry = [
    ...GroundGrid.withoutAxes(100, 100).build(),
  ];

  static final _initialCameraPosition = CameraConfig(
    position: Vertex(Vector3(150, -100, 135)),
    yaw: math.pi / 4,
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
    if (_enteringSketch) return;
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
      if (_cameraAnimation.isCompleted && _enteringSketch) {
        _enteringSketch = false;
      }
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
      _selectedHit = hit;
      _selectedReference = hit?.edge == null ? hit?.faceReference : null;
      _selectedFeature = (hit?.bodyReference ?? hit?.faceReference)?.featureId;
    });
    if (_selectingSketchPlane &&
        hit?.faceReference != null &&
        hit!.face.surface is PlaneSurface) {
      final normal = (hit.face.surface as PlaneSurface).normal;
      _enterSketch(
        support: PlanarSupport.face(
          reference: hit.faceReference!,
          preferredDirection: normal.x.abs() < 0.9
              ? Vector3(1, 0, 0)
              : Vector3(0, 1, 0),
        ),
      );
    }
  }

  void _documentChanged() {
    _evaluated = _document.evaluation.materializeGeometry();
    if (_selectedHit != null) _selectedReference = null;
    _selectedHit = null;
    if (_selectedReference != null &&
        !{
          ..._evaluated.faces.values,
          ..._evaluated.bodies.values,
        }.contains(_selectedReference)) {
      _selectedReference = null;
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
      _selectedHit = null;
    });
  }

  void _editorChanged() {
    if (_editor.activeId == null && _previousCamera != null) {
      _cameraAnimation.stop();
      _enteringSketch = false;
      _cameraPosition = _previousCamera!;
      _previousCamera = null;
    }
    final frame = _editor.support?.frame;
    if (frame != null && !_enteringSketch) {
      final x = CameraProjection(_sketchCamera(_editor.view))
          .toCameraDirection(frame.xAxis);
      _editor.view = SketchView(
        scale: _editor.view.scale,
        center: _editor.view.center,
        rotation: math.atan2(x.z, x.x),
      );
    }
    if (mounted) setState(() {});
  }

  void _startSketchSelection() {
    if (_selectingSketchPlane || _enteringSketch) return;
    setState(() {
      _selectingSketchPlane = true;
      _selectedReference = null;
      _selectedHit = null;
    });
  }

  void _cancelSketchSelection() {
    if (_selectingSketchPlane) {
      setState(() => _selectingSketchPlane = false);
    } else if (_selectedHit != null || _selectedReference != null) {
      setState(() {
        _selectedHit = null;
        _selectedReference = null;
        _selectedFeature = null;
      });
    }
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
    _selectingSketchPlane = false;
    final frame = _editor.support?.frame;
    if (frame == null) {
      setState(() {});
      return;
    }
    final direction = -frame.normal;
    final yaw = _planeYaw(direction);
    final turn =
        (yaw - _cameraPosition.yaw + math.pi) % (2 * math.pi) - math.pi;
    final target = CameraConfig(
      position: Vertex(frame.origin - direction * 200),
      yaw: _cameraPosition.yaw + turn,
      pitch: math.asin(direction.z.clamp(-1.0, 1.0)),
      focalLength: 500,
      focusDistance: 200,
      isOrthographic: true,
    );
    final projection = CameraProjection(target);
    final x = projection.toCameraDirection(frame.xAxis);
    _editor.view = SketchView(
      scale: target.focalLength / target.focusDistance,
      rotation: math.atan2(x.z, x.x),
    );
    _enteringSketch = true;
    _animateTo(target);
    setState(() {});
  }

  double _planeYaw(Vector3 direction) =>
      direction.x.abs() + direction.y.abs() < 1e-12
      ? 0
      : math.atan2(-direction.x, direction.y);

  CameraConfig _sketchCamera(SketchView view) {
    final frame = _editor.support?.frame;
    if (frame == null) return _cameraPosition;
    final center = frame.localToWorld(Vector2(view.center.dx, view.center.dy));
    final direction = -frame.normal;
    return _cameraPosition.copyWith(
      yaw: _planeYaw(direction),
      pitch: math.asin(direction.z.clamp(-1.0, 1.0)),
      position: Vertex(center + frame.normal * _cameraPosition.focusDistance),
      focalLength: view.scale * _cameraPosition.focusDistance,
      isOrthographic: true,
    );
  }

  Widget _scene(CameraConfig camera, {bool editing = false}) => CadScene(
    cameraConfig: camera,
    sketches: [
      for (final result in _document.evaluation.features.entries)
        if (result.value.state == FeatureState.valid &&
            (!editing || result.key != _editor.activeId))
          for (final output in result.value.outputs)
            if (output.kind == OutputKind.sketch) output.data as SketchGeometry,
    ],
    renderMode: CadRenderMode.shaded,
    geometry: _geometry,
    evaluatedGeometry: _evaluated,
    selectionMode: _selectingSketchPlane
        ? ViewportSelectionMode.planarFace
        : ViewportSelectionMode.inspect,
    onSelected: _enteringSketch || editing ? null : _select,
    selectedReference: editing ? null : _selectedReference,
    selectedHit: editing ? null : _selectedHit,
    geometryRevision: _document.evaluation.revision,
    showPrincipalPlanes: _selectingSketchPlane,
    onPrincipalPlaneSelected: (plane) =>
        _enterSketch(support: PlanarSupport.principal(plane)),
  );

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

  @override
  Widget build(BuildContext context) {
    if (_extrusionEditor.activeId != null) {
      return Scaffold(body: ExtrusionWorkspace(editor: _extrusionEditor));
    }
    if (_editor.activeId != null && !_enteringSketch) {
      return Scaffold(
        body: SketchWorkspace(
          editor: _editor,
          onClose: _leaveSketch,
          onExtrude: _extrudeSketch,
          sceneBuilder: (view) => _scene(_sketchCamera(view), editing: true),
        ),
      );
    }
    final evaluated = _evaluated;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            _cancelSketchSelection,
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
                        child: FeatureHistoryPanel(
                          document: _document,
                          selectedId: _selectedFeature,
                          onSelected: _selectFeature,
                          onOpenSketch: (id) => _enterSketch(id: id),
                          onEditExtrusion: _extrusionEditor.open,
                          onExtrudeSketch: _enterExtrusion,
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerPanZoomStart: (_) {
                        if (_enteringSketch) return;
                        _cameraAnimation.stop();
                        _previousGestureScale = 1.0;
                      },
                      onPointerPanZoomUpdate: (event) {
                        if (_enteringSketch) return;
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
                          AbsorbPointer(
                            absorbing: _enteringSketch,
                            child: _scene(_cameraPosition),
                          ),
                          if (!_enteringSketch &&
                              !_selectingSketchPlane &&
                              _selectedHit != null)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 16,
                              child: Center(
                                child: SelectionBadge(
                                  key: const Key('selection-badge'),
                                  measurement: SelectionMeasurement.fromHit(
                                    _selectedHit!,
                                  ),
                                ),
                              ),
                            ),
                          if (!_enteringSketch)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Material(
                                  elevation: 3,
                                  color: _selectingSketchPlane
                                      ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                      : Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(10),
                                  child: IconButton(
                                    key: const Key('start-sketch'),
                                    tooltip: 'Sketch',
                                    onPressed: _startSketchSelection,
                                    iconSize: 32,
                                    padding: const EdgeInsets.all(10),
                                    icon: Image.asset(
                                      'assets/icons/sketch.png',
                                      semanticLabel: 'Sketch',
                                      width: 32,
                                      height: 32,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_selectingSketchPlane)
                            Positioned(
                              top: 16,
                              left: 96,
                              right: 96,
                              child: Center(
                                child: IgnorePointer(
                                  child: Material(
                                    key: const Key('sketch-plane-hint'),
                                    elevation: 2,
                                    borderRadius: BorderRadius.circular(20),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        'Hint: select plane to start sketch on it',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: ViewCube(
                              camera: _cameraPosition,
                              onSelected: (side) {
                                if (!_enteringSketch) _selectSide(side);
                              },
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
