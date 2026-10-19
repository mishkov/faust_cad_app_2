import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter/material.dart';

import '../sketch/sketch_geometry.dart';
import '../sketch_editor/presentation/sketch_scene_painter.dart';
import 'cad_render_backend.dart';
import '../document/planar_support.dart';
import 'cad_surfaces/plane_surface.dart';
import 'rendering/scene_guides_painter.dart';
import 'selection/principal_plane_views.dart';
import 'rendering/metal/metal_viewport.dart';
import 'rendering/metal/metal_viewport_controller.dart';

import '../document/evaluated_geometry.dart';
import '../document/output_reference.dart';
import 'cad_primitivies/face.dart';
import 'cad_primitivies/edge.dart';
import 'cad_primitivies/solid.dart';
import 'cad_primitivies/shell.dart';
import 'cad_surfaces/cylinder_surface.dart';
import 'geometry/analytic_continuity.dart';
import 'selection/viewport_picker.dart';
import 'selection/viewport_hit.dart';

export 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';

export 'cad_render_backend.dart';
export 'selection/viewport_hit.dart';
export 'selection/viewport_picker.dart';

export 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';

class CadScene extends StatefulWidget {
  const new({
    super.key,
    required this.cameraConfig,
    this.cadObjects = const [],
    this.geometry,
    this.renderMode = CadRenderMode.frame,
    this.tessellationSettings,
    this.geometryRevision,
    this.showPrincipalPlanes = false,
    this.onPrincipalPlaneSelected,
    this.evaluatedGeometry,
    this.selectionMode = ViewportSelectionMode.planarFace,
    this.onSelected,
    this.selectedReference,
    this.selectedHit,
    this._backend,
    this.sketches = const [],
    this.metalController,
  });

  final CadRenderBackend? _backend;
  CadRenderBackend get backend => _backend ?? CadRenderBackend.configured;
  final List<SketchGeometry> sketches;
  final MetalViewportController? metalController;
  final EvaluatedGeometry? evaluatedGeometry;
  final ViewportSelectionMode selectionMode;
  final ValueChanged<ViewportHit?>? onSelected;
  final OutputReference? selectedReference;
  final ViewportHit? selectedHit;
  final bool showPrincipalPlanes;
  final ValueChanged<PrincipalPlane>? onPrincipalPlaneSelected;
  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;
  final List<CadPrimitive>? geometry;

  /// Defaults to the existing wireframe appearance.
  final CadRenderMode renderMode;
  final TessellationSettings? tessellationSettings;

  /// Change to explicitly invalidate derived geometry after model edits.
  final Object? geometryRevision;

  @override
  State<CadScene> createState() => _CadSceneState();
}

class _CadSceneState extends State<CadScene> {
  final _tessellator = SceneTessellator();
  static final _emptyGeometry = EvaluatedGeometry(
    geometry: [],
    bodies: {},
    faces: {},
  );
  Offset? _hoverPosition;
  Face? _hoveredFace;
  Edge? _hoveredEdge;
  @override
  Widget build(BuildContext context) {
    final evaluated = widget.evaluatedGeometry;
    final picker = ViewportPicker(
      evaluated: evaluated ?? _emptyGeometry,
      extraGeometry: [
        ...?widget.geometry,
        for (final o in widget.cadObjects) ...o.build(),
      ],
      tessellator: _tessellator,
      settings: widget.tessellationSettings,
      geometryRevision: widget.geometryRevision,
    );
    final selectedFaces = <Face>{};
    final selectedHit = widget.selectedHit;
    final selectedEdge = selectedHit?.edge;
    if (selectedHit != null && selectedEdge == null) {
      selectedFaces.add(selectedHit.face);
      if (selectedHit.face.surface is CylinderSurface) {
        selectedFaces.addAll(
          AnalyticContinuity.connectedCylinderFaces(
            selectedHit.face,
            _facesOf(selectedHit.owner),
          ),
        );
      }
    }
    if (evaluated != null &&
        widget.selectedReference != null &&
        selectedEdge == null) {
      for (final entry in evaluated.faces.entries) {
        if (entry.value == widget.selectedReference) {
          selectedFaces.add(entry.key);
        }
      }
      for (final entry in evaluated.bodies.entries) {
        if (entry.value == widget.selectedReference && entry.key is Solid) {
          selectedFaces.addAll(
            (entry.key as Solid).shells.expand((s) => s.faces),
          );
        }
      }
    }
    final scene = picker.scene;
    return LayoutBuilder(
      builder: (context, constraints) {
        ViewportHit? hitAt(Offset position) => picker.pick(
          camera: widget.cameraConfig,
          viewport: constraints.biggest,
          position: position,
          mode: widget.showPrincipalPlanes
              ? ViewportSelectionMode.planarFace
              : widget.selectionMode == ViewportSelectionMode.inspect
              ? ViewportSelectionMode.inspect
              : ViewportSelectionMode.face,
        );

        final hover = _hoverPosition == null ? null : hitAt(_hoverPosition!);
        _hoveredEdge = hover?.edge;
        _hoveredFace = _hoveredEdge == null ? hover?.face : null;
        final Widget paint = widget.backend == CadRenderBackend.metal
            ? MetalViewport(
                scene: scene,
                camera: widget.cameraConfig,
                renderMode: widget.renderMode,
                selectedFaces: selectedFaces,
                selectedEdge: selectedEdge,
                hoveredFace: _hoveredFace,
                hoveredEdge: _hoveredEdge,
                sketches: widget.sketches,
                controller: widget.metalController,
              )
            : CustomPaint(
                painter: CadScenePainter(
                  cameraConfig: widget.cameraConfig,
                  showGuides: true,
                  showPrincipalPlanes: widget.showPrincipalPlanes,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  evaluatedScene: scene,
                  selectedFaces: selectedFaces,
                  selectedEdge: selectedEdge,
                  hoveredFace: _hoveredFace,
                  hoveredEdge: _hoveredEdge,
                  cadObjects: widget.cadObjects,
                  geometry: widget.geometry,
                  renderMode: widget.renderMode,
                  tessellationSettings: widget.tessellationSettings,
                  geometryRevision: widget.geometryRevision,
                  tessellator: _tessellator,
                ),
              );
        final contents =
            widget.backend == CadRenderBackend.canvas &&
                widget.sketches.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  paint,
                  IgnorePointer(
                    child: CustomPaint(
                      painter: SketchScenePainter(
                        sketches: widget.sketches,
                        camera: widget.cameraConfig,
                        occluders: scene,
                      ),
                    ),
                  ),
                ],
              )
            : paint;
        final guidedContents = widget.backend == CadRenderBackend.metal
            ? CustomPaint(
                foregroundPainter: SceneGuidesPainter(
                  camera: widget.cameraConfig,
                  occluders: scene,
                  showPlanes: widget.showPrincipalPlanes,
                ),
                child: contents,
              )
            : contents;
        final interactive = MouseRegion(
          onHover: (event) {
            _hoverPosition = event.localPosition;
            final hit = hitAt(event.localPosition);
            final edge = hit?.edge;
            final face = edge == null ? hit?.face : null;
            if (face != _hoveredFace || edge != _hoveredEdge) {
              setState(() {
                _hoveredFace = face;
                _hoveredEdge = edge;
              });
            }
          },
          onExit: (_) {
            _hoverPosition = null;
            if (_hoveredFace != null || _hoveredEdge != null) {
              setState(() {
                _hoveredFace = null;
                _hoveredEdge = null;
              });
            }
          },
          child: guidedContents,
        );
        if (widget.onSelected == null) return interactive;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (event) {
            final hit = picker.pick(
              camera: widget.cameraConfig,
              viewport: constraints.biggest,
              position: event.localPosition,
              mode: widget.showPrincipalPlanes
                  ? ViewportSelectionMode.body
                  : widget.selectionMode,
            );
            if (widget.showPrincipalPlanes) {
              final plane = PrincipalPlaneViews.pick(
                widget.cameraConfig,
                constraints.biggest,
                event.localPosition,
              );
              if (plane != null && (hit == null || plane.depth < hit.depth)) {
                widget.onPrincipalPlaneSelected?.call(plane.plane);
                return;
              }
              if (hit?.face.surface is! PlaneSurface) return;
            }
            widget.onSelected!(hit);
          },
          child: interactive,
        );
      },
    );
  }

  Iterable<Face> _facesOf(CadPrimitive owner) => switch (owner) {
    Solid(:final shells) => shells.expand((shell) => shell.faces),
    Shell(:final faces) => faces,
    Face() => [owner],
    _ => const [],
  };
}
