import 'package:faust_cad_app_2/cad_scene/cad_objects/cad_object.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene_painter.dart';
import 'package:faust_cad_app_2/cad_scene/camera_config.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/scene_tessellator.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/tessellation/tessellation_settings.dart';
import 'package:flutter/material.dart';

import '../document/evaluated_geometry.dart';
import '../document/output_reference.dart';
import 'cad_primitivies/face.dart';
import 'cad_primitivies/solid.dart';
import 'selection/viewport_picker.dart';
import 'selection/viewport_hit.dart';
import 'rendering/cad_render_backend.dart';
import 'rendering/gpu/gpu_viewport_stub.dart'
    if (dart.library.io) 'rendering/gpu/gpu_viewport.dart';

export 'rendering/cad_render_backend.dart';

export 'package:faust_cad_app_2/cad_scene/cad_render_mode.dart';

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
    this.evaluatedGeometry,
    this.selectionMode = ViewportSelectionMode.planarFace,
    this.onSelected,
    this.selectedReference,
    this.backend = CadRenderBackend.developmentDefault,
  });

  final EvaluatedGeometry? evaluatedGeometry;
  final ViewportSelectionMode selectionMode;
  final ValueChanged<ViewportHit?>? onSelected;
  final OutputReference? selectedReference;
  final CameraConfig cameraConfig;
  final List<CadObject> cadObjects;
  final List<CadPrimitive>? geometry;

  /// Defaults to the existing wireframe appearance.
  final CadRenderMode renderMode;
  final TessellationSettings? tessellationSettings;

  /// Change to explicitly invalidate derived geometry after model edits.
  final Object? geometryRevision;
  final CadRenderBackend backend;

  @override
  State<CadScene> createState() => _CadSceneState();
}

class _CadSceneState extends State<CadScene> {
  final _tessellator = SceneTessellator();
  @override
  Widget build(BuildContext context) {
    final evaluated = widget.evaluatedGeometry;
    final picker = evaluated == null
        ? null
        : ViewportPicker(
            evaluated: evaluated,
            extraGeometry: [
              ...?widget.geometry,
              for (final o in widget.cadObjects) ...o.build(),
            ],
            tessellator: _tessellator,
            settings: widget.tessellationSettings,
            geometryRevision: widget.geometryRevision,
          );
    final selectedFaces = <Face>{};
    if (evaluated != null && widget.selectedReference != null) {
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
    final Widget paint;
    if (widget.backend == CadRenderBackend.flutterGpu &&
        widget.renderMode == CadRenderMode.shaded) {
      final scene =
          picker?.scene ??
          _tessellator.buildGeometry(
            [
              ...?widget.geometry,
              for (final object in widget.cadObjects) ...object.build(),
            ],
            settings: widget.tessellationSettings,
            geometryRevision: widget.geometryRevision,
          );
      paint = GpuViewport(
        camera: widget.cameraConfig,
        scene: scene,
        selected: selectedFaces,
      );
    } else {
      paint = CustomPaint(
        painter: CadScenePainter(
          cameraConfig: widget.cameraConfig,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          evaluatedScene: picker?.scene,
          selectedFaces: selectedFaces,
          cadObjects: widget.cadObjects,
          geometry: widget.geometry,
          renderMode: widget.renderMode,
          tessellationSettings: widget.tessellationSettings,
          geometryRevision: widget.geometryRevision,
          tessellator: _tessellator,
        ),
      );
    }
    if (picker == null || widget.onSelected == null) return paint;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (event) => widget.onSelected!(
          picker.pick(
            camera: widget.cameraConfig,
            viewport: constraints.biggest,
            position: event.localPosition,
            mode: widget.selectionMode,
          ),
        ),
        child: paint,
      ),
    );
  }
}
