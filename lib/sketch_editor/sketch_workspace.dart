import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sketch/sketch.dart';
import 'presentation/sketch_constraint_marker.dart';
import 'presentation/sketch_painter.dart';
import 'sketch_editor_controller.dart';
import 'sketch_dimension_dialog.dart';
import 'sketch_hit.dart';
import 'sketch_interaction.dart';
import 'sketch_view.dart';

class SketchWorkspace extends StatefulWidget {
  const SketchWorkspace({
    super.key,
    required this.editor,
    required this.onClose,
    this.onExtrude,
    this.sceneBuilder,
  });
  final SketchEditorController editor;
  final VoidCallback onClose;
  final VoidCallback? onExtrude;
  final Widget Function(SketchView view)? sceneBuilder;
  @override
  State<SketchWorkspace> createState() => _SketchWorkspaceState();
}

class _SketchWorkspaceState extends State<SketchWorkspace> {
  final _drawingDimension = TextEditingController();
  final _canvasFocus = FocusNode();
  Offset? _down;
  SketchHit? _downHit;
  bool _panning = false;
  bool _moved = false;
  double _gestureScale = 1;
  SketchEditorController get editor => widget.editor;

  @override
  void dispose() {
    _drawingDimension.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  Future<double?> _dimension(
    String title, {
    double? current,
    bool allowZero = false,
  }) async {
    return showDialog<double>(
      context: context,
      builder: (context) => SketchDimensionDialog(
        title: title,
        current: current,
        allowZero: allowZero,
      ),
    );
  }

  Future<void> _addConstraint(SketchConstraintKind kind) async {
    final owner = editor.activeId;
    final value = SketchEditorController.isDimension(kind)
        ? await _dimension(
            _label(kind),
            allowZero: kind == SketchConstraintKind.distance,
          )
        : null;
    if (!mounted || editor.activeId != owner) return;
    editor.addConstraint(kind, dimension: value);
    _canvasFocus.requestFocus();
  }

  Future<void> _editDimension(SketchConstraint constraint) async {
    final owner = editor.activeId;
    final value = await _dimension(
      _label(constraint.kind),
      current: constraint.values.single,
      allowZero: constraint.kind == SketchConstraintKind.distance,
    );
    if (mounted && value != null && editor.activeId == owner) {
      editor.editDimension(constraint.id, value);
    }
    _canvasFocus.requestFocus();
  }

  static String _label(SketchConstraintKind kind) => switch (kind) {
    SketchConstraintKind.coincident => 'Coincident',
    SketchConstraintKind.pointOnLine => 'Point on line',
    SketchConstraintKind.pointOnCircle => 'Point on circle',
    SketchConstraintKind.horizontal => 'Horizontal',
    SketchConstraintKind.vertical => 'Vertical',
    SketchConstraintKind.parallel => 'Parallel',
    SketchConstraintKind.perpendicular => 'Perpendicular',
    SketchConstraintKind.lineLength => 'Length',
    SketchConstraintKind.distance => 'Distance',
    SketchConstraintKind.radius => 'Radius',
    SketchConstraintKind.diameter => 'Diameter',
    SketchConstraintKind.equalLengths => 'Equal lengths',
    SketchConstraintKind.equalRadii => 'Equal radii',
    SketchConstraintKind.fixedPoint => 'Fix point',
    SketchConstraintKind.fixedPrimitive => 'Fix primitive',
  };

  Widget _panel() {
    final definition = editor.definition;
    final solution = editor.solution;
    return SizedBox(
      width: widget.sceneBuilder == null ? 280 : 300,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sketch ${editor.activeId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              editor.support == null
                  ? 'Support unavailable'
                  : '${definition!.support.principalPlane?.name.toUpperCase() ?? 'Attached face'} • infinite plane',
            ),
            const SizedBox(height: 8),
            Text(
              '${switch (solution?.status) {
                SketchSolveStatus.underconstrained => 'Underconstrained',
                SketchSolveStatus.fullyConstrained => 'Fully constrained',
                SketchSolveStatus.redundant => 'Redundant constraints',
                SketchSolveStatus.conflicting => 'Conflicting constraints',
                SketchSolveStatus.numericalFailure => 'Numerical failure',
                null => 'Unavailable',
              }} • ${solution?.degreesOfFreedom?.toString() ?? '?'} degrees of freedom',
            ),
            if (editor.supportDiagnostic != null)
              Text(
                '${editor.supportDiagnostic}\nRestore the supporting face or undo its change.',
                style: const TextStyle(color: Colors.red),
              ),
            if (solution?.isValid == false)
              const Text(
                'Solve failed. Edit or remove the listed constraints, or undo. Geometry and regions are withheld.',
                style: TextStyle(color: Colors.red),
              ),
            for (final d in [
              ...?solution?.diagnostics,
              ...?editor.dragDiagnostic?.diagnostics,
            ])
              Text(
                '${d.constraintId ?? 'Solver'}: ${d.message}${d.residual == null ? '' : ' (residual ${d.residual})'}',
                style: const TextStyle(color: Colors.red),
              ),
            if (solution?.redundantConstraintIds.isNotEmpty == true)
              Text(
                'Redundant: ${solution!.redundantConstraintIds.join(', ')}. Remove duplicates if unintended.',
              ),
            if (editor.message != null)
              Text(editor.message!, style: const TextStyle(color: Colors.red)),
            const Divider(),
            const Text(
              'Shift-click to select several entities. Alt-click cycles overlapping hits. Points take priority over curves, markers, then filled regions.',
            ),
            const SizedBox(height: 8),
            Text(
              'Selected: ${editor.selected.isEmpty ? 'none' : editor.selected.join(', ')}',
            ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final kind in editor.availableConstraints)
                  OutlinedButton(
                    onPressed: () => _addConstraint(kind),
                    child: Text(_label(kind)),
                  ),
              ],
            ),
            if (editor.selected.isNotEmpty)
              TextButton.icon(
                key: const Key('delete-selection'),
                onPressed: editor.deleteSelection,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete selection'),
              ),
            const Divider(),
            const Text('Persistent constraints'),
            if (definition?.constraints.isEmpty == true)
              const Text('None. Snapping only places coordinates.'),
            for (final constraint
                in definition?.constraints.values ?? <SketchConstraint>[])
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                selected: editor.selectedConstraint == constraint.id,
                title: Text(
                  '${_label(constraint.kind)} ${SketchEditorController.isDimension(constraint.kind) ? constraint.values.single.toStringAsFixed(3) : ''}',
                ),
                subtitle: Text(
                  '${constraint.id} • ${constraint.references.join(', ')}',
                ),
                onTap: () {
                  editor.selectConstraint(constraint.id);
                  _canvasFocus.requestFocus();
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (SketchEditorController.isDimension(constraint.kind))
                      IconButton(
                        tooltip: 'Edit dimension',
                        onPressed: () => _editDimension(constraint),
                        icon: const Icon(Icons.edit, size: 18),
                      ),
                    IconButton(
                      tooltip: 'Remove constraint',
                      onPressed: () => editor.removeConstraint(constraint.id),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              '${editor.regions?.regions.length ?? 0} filled regions • ${editor.selectedRegionIds.length} selected',
            ),
            if (editor.profileDiagnostic != null)
              Text(
                editor.profileDiagnostic!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            for (final diagnostic in editor.regions?.diagnostics ?? [])
              Text(diagnostic.message),
            const Text(
              'Gaps are never bridged. Add Coincident to distinct endpoints for persistent closure.',
            ),
            const Divider(),
            const Text('Entities'),
            for (final point in definition?.points.values ?? <SketchPoint>[])
              _entityRow(point.id, 'Point'),
            for (final line
                in definition?.segments.values ?? <SketchLineSegment>[])
              _entityRow(line.id, 'Line'),
            for (final circle in definition?.circles.values ?? <SketchCircle>[])
              _entityRow(circle.id, 'Circle'),
          ],
        ),
      ),
    );
  }

  Widget _entityRow(SketchEntityId id, String type) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text('$type $id'),
    value: editor.selected.contains(id),
    onChanged: (_) {
      editor.selectEntity(id, additive: true);
      _canvasFocus.requestFocus();
    },
  );

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      return Focus(
        focusNode: _canvasFocus,
        autofocus: true,
        child: Listener(
          key: const Key('sketch-canvas'),
          behavior: HitTestBehavior.opaque,
          onPointerHover: (e) => editor.hover(e.localPosition, size),
          onPointerDown: (e) {
            _canvasFocus.requestFocus();
            _down = e.localPosition;
            _moved = false;
            _panning =
                e.buttons == kMiddleMouseButton ||
                e.buttons == kSecondaryMouseButton;
            _downHit = editor.presentation
                ?.hits(e.localPosition, editor.view, size)
                .firstOrNull;
          },
          onPointerMove: (e) {
            if (_down == null) return;
            if (_panning) {
              editor.updateView(editor.view.pan(e.delta));
              _moved = true;
              return;
            }
            if ((e.localPosition - _down!).distance > 4) {
              _moved = true;
              if (editor.interaction != SketchInteraction.dragging &&
                  editor.tool == SketchTool.select &&
                  _downHit?.entityId != null) {
                editor.beginDrag(
                  _downHit!.entityId!,
                  editor.view.unproject(_down!, size),
                );
              }
            }
            if (editor.interaction == SketchInteraction.dragging) {
              editor.updateDrag(editor.view.unproject(e.localPosition, size));
            } else {
              editor.hover(e.localPosition, size);
            }
          },
          onPointerUp: (e) {
            if (_down == null) return;
            if (editor.interaction == SketchInteraction.dragging) {
              editor.endDrag();
            } else if (!_panning && !_moved) {
              final hits =
                  editor.presentation?.hits(
                    e.localPosition,
                    editor.view,
                    size,
                  ) ??
                  [];
              final markers = editor.solution?.geometry == null
                  ? <SketchConstraintMarker>[]
                  : SketchConstraintMarker.build(
                      editor.definition!,
                      editor.solution!.geometry!,
                      editor.view,
                      size,
                    );
              final marker = markers
                  .where((m) => m.bounds.contains(e.localPosition))
                  .firstOrNull;
              if (editor.tool == SketchTool.select &&
                  marker != null &&
                  (hits.isEmpty || hits.first.kind == SketchHitKind.region)) {
                editor.selectConstraint(marker.constraint.id);
                if (SketchEditorController.isDimension(
                  marker.constraint.kind,
                )) {
                  _editDimension(marker.constraint);
                }
              } else {
                editor.tap(
                  e.localPosition,
                  size,
                  additive: HardwareKeyboard.instance.isShiftPressed,
                  cycle: HardwareKeyboard.instance.isAltPressed,
                );
              }
            }
            _down = null;
            _downHit = null;
            _panning = false;
          },
          onPointerCancel: (_) {
            editor.cancel();
            _down = null;
            _downHit = null;
            _panning = false;
          },
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              editor.updateView(
                editor.view.zoom(
                  e.localPosition,
                  size,
                  math.exp(-e.scrollDelta.dy * 0.002),
                ),
              );
            }
          },
          onPointerPanZoomStart: (_) => _gestureScale = 1,
          onPointerPanZoomUpdate: (e) {
            editor.updateView(
              editor.view
                  .pan(e.panDelta)
                  .zoom(e.localPosition, size, e.scale / _gestureScale),
            );
            _gestureScale = e.scale;
          },
          onPointerPanZoomEnd: (_) => _gestureScale = 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.sceneBuilder != null)
                IgnorePointer(child: widget.sceneBuilder!(editor.view)),
              CustomPaint(
                painter: SketchPainter(
                  editor,
                  overlay: widget.sceneBuilder != null,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _layout(Widget toolbar, Widget instructions) {
    if (widget.sceneBuilder == null) {
      return Column(
        children: [
          toolbar,
          instructions,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _panel(),
                Expanded(child: _canvas()),
              ],
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: Column(
            children: [
              toolbar,
              instructions,
              Expanded(child: _panel()),
            ],
          ),
        ),
        Expanded(child: _canvas()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: editor,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): editor.cancel,
        const SingleActivator(LogicalKeyboardKey.delete):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.backspace):
            editor.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): editor.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            editor.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            editor.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): editor.redo,
      },
      child: _layout(
        Material(
          color: const Color(0xffedf1f5),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tool in SketchTool.values)
                  OutlinedButton(
                    key: Key('tool-${tool.name}'),
                    style: editor.tool == tool
                        ? OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xffd4e6f7),
                          )
                        : null,
                    onPressed: editor.editable
                        ? () {
                            editor.setTool(tool);
                            _canvasFocus.requestFocus();
                          }
                        : null,
                    child: Text(switch (tool) {
                      SketchTool.select => 'Select',
                      SketchTool.line => 'Line',
                      SketchTool.circle => 'Circle',
                    }),
                  ),
                TextButton(
                  onPressed: editor.cancel,
                  child: const Text('Cancel drawing (Esc)'),
                ),
                IconButton(
                  tooltip: 'Undo',
                  onPressed:
                      editor.document.canUndo ||
                          editor.interaction == SketchInteraction.dragging
                      ? editor.undo
                      : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: editor.document.canRedo ? editor.redo : null,
                  icon: const Icon(Icons.redo),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: editor.snapping,
                      onChanged: (value) {
                        editor.setSnapping(value!);
                      },
                    ),
                    const Text('Snap placement'),
                  ],
                ),
                SizedBox(
                  width: 150,
                  height: 48,
                  child: TextField(
                    key: const Key('drawing-dimension'),
                    enabled: editor.anchor != null,
                    controller: _drawingDimension,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: editor.tool == SketchTool.line
                          ? 'Length'
                          : editor.tool == SketchTool.circle
                          ? 'Radius'
                          : 'Dimension',
                      suffixText: 'units',
                    ),
                    onSubmitted: (text) {
                      final value = double.tryParse(text);
                      if (value == null) {
                        editor.showMessage(
                          'Enter a positive finite dimension.',
                        );
                      } else {
                        editor.finishDrawing(dimension: value);
                        _drawingDimension.clear();
                        _canvasFocus.requestFocus();
                      }
                    },
                  ),
                ),
                if (widget.onExtrude != null)
                  OutlinedButton(
                    key: const Key('extrude-sketch'),
                    onPressed: editor.editable ? widget.onExtrude : null,
                    child: const Text('Extrude regions'),
                  ),
                OutlinedButton(
                  key: const Key('cancel-sketch'),
                  onPressed: editor.cancelSketch,
                  child: const Text('Cancel sketch'),
                ),
                FilledButton(
                  key: const Key('finish-sketch'),
                  onPressed: widget.onClose,
                  child: const Text('Finish sketch'),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 40,
              child: Text(
                switch (editor.interaction) {
                  SketchInteraction.idle => 'Select or drag • scroll to zoom • middle/right drag to pan',
                  SketchInteraction.lineStart => 'Click the first endpoint',
                  SketchInteraction.lineEnd => 'Click the endpoint, or enter a length to commit a dimension',
                  SketchInteraction.circleCenter => 'Click the circle center',
                  SketchInteraction.circleRadius => 'Click the radius point, or enter a radius to commit a dimension',
                  SketchInteraction.dragging => 'Dragging with persistent constraints • release to commit • Esc to restore',
                },
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
