import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

import '../cad_scene/cad_primitivies/vertex.dart';
import '../cad_scene/cad_scene.dart';
import '../cad_scene/camera_config.dart';
import '../planar_regions/planar_region.dart';
import '../sketch_editor/presentation/sketch_presentation.dart';
import '../sketch_editor/sketch_view.dart';
import 'extrusion_editor_controller.dart';
import 'extrusion_profile_painter.dart';

class ExtrusionWorkspace extends StatefulWidget {
  const ExtrusionWorkspace({super.key, required this.editor});
  final ExtrusionEditorController editor;
  @override
  State<ExtrusionWorkspace> createState() => _ExtrusionWorkspaceState();
}

class _ExtrusionWorkspaceState extends State<ExtrusionWorkspace> {
  late final _distance = TextEditingController(
    text: widget.editor.distanceText,
  );
  SketchView? _view;
  double _gestureScale = 1;
  double _previewYaw = -0.5;
  double _previewPitch = -0.65;
  double _previewZoom = 1;

  SketchView _fit(Size size) {
    final points = [
      for (final r in widget.editor.regions?.regions ?? [])
        ...SketchPresentation.sampleLoop(r.outer),
      ...?widget.editor.sketch?.solved.points.values.map((p) => p.position),
    ];
    if (points.isEmpty) return const SketchView();
    final minX = points.map((p) => p.x).reduce(math.min),
        maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min),
        maxY = points.map((p) => p.y).reduce(math.max);
    return SketchView(
      center: Offset((minX + maxX) / 2, (minY + maxY) / 2),
      scale:
          math.min(
            size.width / math.max(1, maxX - minX),
            size.height / math.max(1, maxY - minY),
          ) *
          0.7,
    );
  }

  Widget _profiles() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final view = _view ?? _fit(size);
      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            setState(
              () => _view = view.zoom(
                e.localPosition,
                size,
                math.exp(-e.scrollDelta.dy * 0.002),
              ),
            );
          }
        },
        onPointerPanZoomStart: (_) => _gestureScale = 1,
        onPointerPanZoomUpdate: (e) {
          setState(
            () => _view = view
                .pan(e.panDelta)
                .zoom(e.localPosition, size, e.scale / _gestureScale),
          );
          _gestureScale = e.scale;
        },
        child: GestureDetector(
          key: const Key('extrusion-profile-canvas'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (e) {
            final local = view.unproject(e.localPosition, size);
            final hit = widget.editor.regions?.regions
                .where((r) => r.locate(local) == RegionPointLocation.inside)
                .firstOrNull;
            if (hit != null) widget.editor.toggleRegion(hit.id);
          },
          onPanUpdate: (e) => setState(() => _view = view.pan(e.delta)),
          child: CustomPaint(
            painter: ExtrusionProfilePainter(widget.editor, view),
            child: const SizedBox.expand(),
          ),
        ),
      );
    },
  );

  CameraConfig _camera() {
    final frame = widget.editor.sketch?.frame;
    final distance = double.tryParse(widget.editor.distanceText) ?? 10;
    // Keep the camera representable even while an extreme distance is rejected.
    final depth = distance.isFinite && distance > 0
        ? distance.clamp(0.001, 1e6)
        : 10.0;
    final points = [
      for (final r in widget.editor.regions?.regions ?? [])
        ...SketchPresentation.sampleLoop(r.outer),
    ];
    var center = Vector2.zero();
    var span = 20.0;
    if (points.isNotEmpty) {
      final minX = points.map((p) => p.x).reduce(math.min),
          maxX = points.map((p) => p.x).reduce(math.max);
      final minY = points.map((p) => p.y).reduce(math.min),
          maxY = points.map((p) => p.y).reduce(math.max);
      center = Vector2((minX + maxX) / 2, (minY + maxY) / 2);
      span = math.max(10, math.max(maxX - minX, maxY - minY));
    }
    final target = frame == null
        ? Vector3.zero()
        : frame.localToWorld(center) +
              frame.normal * depth * (widget.editor.reverse ? -0.5 : 0.5);
    final forward = Vector3(
      -math.sin(_previewYaw) * math.cos(_previewPitch),
      math.cos(_previewYaw) * math.cos(_previewPitch),
      math.sin(_previewPitch),
    );
    final focus = math.max(span, depth) * 3;
    return CameraConfig(
      position: Vertex(target - forward * focus),
      yaw: _previewYaw,
      pitch: _previewPitch,
      focalLength: 500 * _previewZoom,
      focusDistance: focus,
    );
  }

  Widget _preview() => GestureDetector(
    key: const Key('extrusion-preview'),
    onPanUpdate: (e) => setState(() {
      _previewYaw -= e.delta.dx * 0.01;
      _previewPitch = (_previewPitch - e.delta.dy * 0.01).clamp(-1.5, 1.5);
    }),
    child: Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          setState(
            () => _previewZoom =
                (_previewZoom * math.exp(-e.scrollDelta.dy * 0.002)).clamp(
                  0.1,
                  10,
                ),
          );
        }
      },
      child: CadScene(
        cameraConfig: _camera(),
        renderMode: CadRenderMode.shaded,
        evaluatedGeometry: widget.editor.document.evaluation
            .materializeGeometry(),
        geometryRevision: widget.editor.document.evaluation.revision,
      ),
    ),
  );

  Widget _panel() {
    final editor = widget.editor;
    return SizedBox(
      width: 250,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extrusion ${editor.activeId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Sketch: ${editor.sketchReference?.featureId ?? 'missing'}'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('extrusion-distance'),
              controller: _distance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Distance',
                suffixText: 'units',
              ),
              onChanged: editor.setDistance,
            ),
            SwitchListTile(
              key: const Key('extrusion-reverse'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Reverse'),
              value: editor.reverse,
              onChanged: editor.setReverse,
            ),
            const Text(
              'Click filled regions to toggle selection. Selected regions unite; disconnected components create new bodies.',
            ),
            Text('${editor.selectedRegionIds.length} regions selected'),
            TextButton(
              key: const Key('extrusion-clear'),
              onPressed: editor.clearSelection,
              child: const Text('Clear selection'),
            ),
            for (final r in editor.regions?.regions ?? [])
              CheckboxListTile(
                key: Key('extrusion-region-${r.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text('Region ${editor.regions!.regions.indexOf(r) + 1}'),
                subtitle: Text(
                  'Area ${r.area.toStringAsFixed(3)} • ${r.holes.length} holes',
                ),
                value: editor.selectedRegionIds.contains(r.id),
                onChanged: (_) => editor.toggleRegion(r.id),
              ),
            for (final message in editor.diagnostics)
              Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.editor,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.editor.cancel,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    key: const Key('confirm-extrusion'),
                    onPressed: widget.editor.canConfirm
                        ? widget.editor.confirm
                        : null,
                    child: const Text('Confirm extrusion'),
                  ),
                  TextButton(
                    key: const Key('cancel-extrusion'),
                    onPressed: widget.editor.cancel,
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _view = null),
                    child: const Text('Fit profiles'),
                  ),
                  const Text('Preview • drag the solid view to rotate'),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _panel(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth < 600
                          ? Column(
                              children: [
                                Expanded(child: _profiles()),
                                Expanded(child: _preview()),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: _profiles()),
                                Expanded(child: _preview()),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _distance.dispose();
    super.dispose();
  }
}
