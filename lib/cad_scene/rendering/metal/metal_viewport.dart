import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../sketch/sketch_geometry.dart';
import '../../cad_primitivies/face.dart';
import '../../cad_primitivies/edge.dart';
import '../../cad_render_mode.dart';
import '../../camera_config.dart';
import '../tessellation/tessellated_scene.dart';
import 'metal_scene_mesh.dart';
import 'metal_sketch_mesh.dart';
import 'metal_viewport_controller.dart';

/// Native drawable presentation. All scene pixels are produced by Metal.
final class MetalViewport extends StatefulWidget {
  const MetalViewport({
    super.key,
    required this.scene,
    required this.camera,
    required this.renderMode,
    this.selectedFaces = const {},
    this.selectedEdge,
    this.hoveredFace,
    this.hoveredEdge,
    this.sketches = const [],
    this.controller,
  });
  final TessellatedScene scene;
  final CameraConfig camera;
  final CadRenderMode renderMode;
  final Set<Face> selectedFaces;
  final Edge? selectedEdge;
  final Face? hoveredFace;
  final Edge? hoveredEdge;
  final List<SketchGeometry> sketches;
  final MetalViewportController? controller;
  @override
  State<MetalViewport> createState() => _MetalViewportState();
}

class _MetalViewportState extends State<MetalViewport> {
  late final _controller = widget.controller ?? MetalViewportController();
  MetalSceneMesh? _mesh;
  MetalSceneMesh? _hoverMesh;
  Face? _hoveredFace;
  Edge? _selectedEdge;
  Edge? _hoveredEdge;
  TessellatedScene? _scene;
  List<SketchGeometry>? _sketches;
  int? _id;
  @override
  void initState() {
    super.initState();
    _controller.initialize();
    _controller.ready.then((id) {
      if (mounted && id >= 0) setState(() => _id = id);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.biggest.isEmpty) {
        final packet = <String, Object>{};
        if (!identical(_scene, widget.scene)) {
          _scene = widget.scene;
          _mesh = MetalSceneMesh(widget.scene);
          packet['mesh'] = _mesh!.message;
        }
        if (!identical(_hoverMesh, _mesh) ||
            _hoveredFace != widget.hoveredFace ||
            _selectedEdge != widget.selectedEdge ||
            _hoveredEdge != widget.hoveredEdge) {
          _hoverMesh = _mesh;
          _hoveredFace = widget.hoveredFace;
          _selectedEdge = widget.selectedEdge;
          _hoveredEdge = widget.hoveredEdge;
          packet['hoverLines'] = _mesh!.hoverLines(
            _hoveredFace,
            selectedEdge: _selectedEdge,
            hoveredEdge: _hoveredEdge,
          );
        }
        if (!listEquals(_sketches, widget.sketches)) {
          _sketches = List.of(widget.sketches);
          packet['sketches'] = [
            for (final sketch in widget.sketches)
              MetalSketchMesh(sketch).message,
          ];
        }
        final camera = widget.camera, p = camera.position.vector;
        final color = Theme.of(context).scaffoldBackgroundColor;
        packet.addAll({
          'camera': Float64List.fromList([
            p.x,
            p.y,
            p.z,
            camera.yaw,
            camera.pitch,
            camera.focalLength,
            constraints.maxWidth,
            constraints.maxHeight,
            MediaQuery.devicePixelRatioOf(context),
            camera.isOrthographic ? camera.focusDistance : 0,
          ]),
          'selection': _mesh!.selection(widget.selectedFaces),
          'hoveredFace': widget.hoveredFace == null
              ? -1
              : _mesh!.faces.indexOf(widget.hoveredFace!),
          'hoveredFaces': _mesh!.hoverFaces(widget.hoveredFace),
          'wireframe': widget.renderMode == CadRenderMode.frame,
          'clear': Float64List.fromList([color.r, color.g, color.b, 1]),
        });
        _controller.update(packet);
      }
      return ValueListenableBuilder<String?>(
        valueListenable: _controller.error,
        builder: (context, error, _) {
          if (error != null) {
            return Center(
              child: SelectableText(
                'Metal viewport unavailable\n$error',
                key: const Key('metal-error'),
              ),
            );
          }
          if (_id == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return AppKitView(
            viewType: 'cad.metal.viewport',
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            layoutDirection: TextDirection.ltr,
            creationParams: {'id': _id},
            creationParamsCodec: const StandardMessageCodec(),
          );
        },
      );
    },
  );
}
