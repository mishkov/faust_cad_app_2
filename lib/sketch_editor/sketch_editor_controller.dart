import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../document/document_controller.dart';
import '../document/feature_definition.dart';
import '../document/feature_id.dart';
import '../document/features/sketch_feature.dart';
import '../document/planar_support.dart';
import '../document/planar_support_resolution.dart';
import '../document/resolved_planar_support.dart';
import '../planar_regions/planar_region_engine.dart';
import '../planar_regions/profile_reference.dart';
import '../planar_regions/region_reference.dart';
import '../planar_regions/region_result.dart';
import '../sketch/sketch.dart';
import 'presentation/sketch_presentation.dart';
import 'sketch_hit.dart';
import 'sketch_interaction.dart';
import 'sketch_snap.dart';
import 'sketch_view.dart';

final class SketchEditorController extends ChangeNotifier {
  SketchEditorController(this.document) {
    document.addListener(_refresh);
  }
  final DocumentController document;
  FeatureId? activeId;
  SketchDefinition? definition;
  SketchSolveResult? solution;
  ResolvedPlanarSupport? support;
  RegionResult? regions;
  String? supportDiagnostic;
  String? message;
  SketchSolveResult? dragDiagnostic;
  SketchTool tool = SketchTool.select;
  SketchInteraction interaction = SketchInteraction.idle;
  SketchView view = const SketchView();
  bool snapping = true;
  final Set<SketchEntityId> selected = {};
  SketchConstraintId? selectedConstraint;
  final List<ProfileReference> _profiles = [];
  Set<String> selectedRegionIds = {};
  String? profileDiagnostic;
  Vector2? anchor;
  SketchSnap? preview;
  SketchDefinition? _dragBefore;
  SketchEntityId? _dragId;
  Vector2? _dragOrigin;
  int _serial = 0;

  List<FeatureDefinition> get sketches =>
      document.features.where((f) => f.type == SketchFeature.type).toList();
  bool get editable =>
      activeId != null && support != null && solution?.isValid == true;
  String get sourceId => '${activeId!.value}/${SketchFeature.outputKey}';
  SketchPresentation? get presentation =>
      support == null || solution?.geometry == null
      ? null
      : SketchPresentation(solved: solution!.geometry!, regions: regions);

  SketchEntityId _entityId() {
    final used = {
      ...definition!.points.keys,
      ...definition!.segments.keys,
      ...definition!.circles.keys,
      ...definition!.retiredIds,
    };
    SketchEntityId id;
    do {
      id = SketchEntityId('entity-${++_serial}');
    } while (used.contains(id));
    return id;
  }

  SketchConstraintId _constraintId() {
    SketchConstraintId id;
    do {
      id = SketchConstraintId('constraint-${++_serial}');
    } while (definition!.constraints.containsKey(id) ||
        definition!.retiredConstraintIds.contains(id));
    return id;
  }

  FeatureId create(PlanarSupport plane) {
    cancel();
    FeatureId id;
    do {
      id = FeatureId('sketch-${++_serial}');
    } while (document.features.any((f) => f.id == id));
    document.addFeature(
      SketchFeature.definition(
        id: id,
        sketch: SketchDefinition(support: plane),
      ),
      label: 'Create sketch',
    );
    open(id);
    return id;
  }

  void open(FeatureId id) {
    cancel();
    if (!sketches.any((f) => f.id == id)) {
      throw ArgumentError('Unknown sketch: $id');
    }
    activeId = id;
    tool = SketchTool.select;
    interaction = SketchInteraction.idle;
    view = const SketchView();
    selected.clear();
    selectedConstraint = null;
    _profiles.clear();
    _refresh();
  }

  void close() {
    cancel();
    activeId = null;
    definition = null;
    solution = null;
    support = null;
    regions = null;
    selected.clear();
    selectedConstraint = null;
    _profiles.clear();
    selectedRegionIds = {};
    notifyListeners();
  }

  void _refresh() {
    final feature = document.features
        .where((f) => f.id == activeId)
        .firstOrNull;
    if (feature == null) {
      activeId = null;
      definition = null;
      solution = null;
      regions = null;
      support = null;
      selected.clear();
      selectedConstraint = null;
      supportDiagnostic = null;
      profileDiagnostic = null;
      _profiles.clear();
      selectedRegionIds = {};
      interaction = SketchInteraction.idle;
      anchor = null;
      preview = null;
    } else {
      definition = SketchFeature.readDefinition(feature);
      final resolved = PlanarSupportResolution.resolve(
        definition!.support,
        document.evaluation,
      );
      support = resolved.support;
      supportDiagnostic = resolved.diagnostic;
      solution = const SketchSolver().solve(definition!);
      // A failed support or solve must never publish stale selectable cells.
      regions = support == null || !solution!.isValid
          ? null
          : const PlanarRegionEngine().build(
              const SketchPlanarAdapter().adaptSolved(solution!.geometry!),
            );
      final ids = {
        ...definition!.points.keys,
        ...definition!.segments.keys,
        ...definition!.circles.keys,
      };
      selected.removeWhere((id) => !ids.contains(id));
      if (!definition!.constraints.containsKey(selectedConstraint)) {
        selectedConstraint = null;
      }
      selectedRegionIds = {};
      profileDiagnostic = null;
      for (final reference in _profiles) {
        final result = regions?.resolveProfile(reference, sourceId: sourceId);
        if (result?.status == RegionResolutionStatus.resolved) {
          selectedRegionIds.add(result!.candidates.single.id);
        } else {
          profileDiagnostic =
              'Selected region ${result?.status.name ?? 'unavailable'}. Restore its boundary or select another region.';
        }
      }
    }
    notifyListeners();
  }

  void setTool(SketchTool value) {
    cancel();
    tool = value;
    interaction = switch (value) {
      SketchTool.select => SketchInteraction.idle,
      SketchTool.line => SketchInteraction.lineStart,
      SketchTool.circle => SketchInteraction.circleCenter,
    };
    selected.clear();
    selectedConstraint = null;
    notifyListeners();
  }

  void hover(Offset position, Size size) {
    if (!editable || interaction == SketchInteraction.dragging) return;
    preview = snapping
        ? presentation!.snap(position, view, size, anchor: anchor)
        : SketchSnap(view.unproject(position, size), '');
    notifyListeners();
  }

  void tap(
    Offset position,
    Size size, {
    bool additive = false,
    bool cycle = false,
  }) {
    if (!editable) return;
    message = null;
    if (tool == SketchTool.select) {
      final hits = presentation!.hits(position, view, size);
      SketchHit? hit = hits.firstOrNull;
      if (cycle && hits.length > 1) {
        final index = hits.indexWhere(
          (h) => h.entityId != null && selected.contains(h.entityId),
        );
        hit = hits[(index + 1) % hits.length];
      }
      selectHit(hit, additive: additive);
      return;
    }
    hover(position, size);
    if (anchor == null) {
      anchor = preview!.position;
      interaction = tool == SketchTool.line
          ? SketchInteraction.lineEnd
          : SketchInteraction.circleRadius;
      notifyListeners();
    } else {
      finishDrawing();
    }
  }

  void selectHit(SketchHit? hit, {bool additive = false}) {
    selectedConstraint = null;
    if (!additive) {
      selected.clear();
      selectedConstraint = null;
      supportDiagnostic = null;
      profileDiagnostic = null;
      _profiles.clear();
    }
    if (hit?.entityId != null) {
      final id = hit!.entityId!;
      if (additive && selected.contains(id)) {
        selected.remove(id);
      } else {
        selected.add(id);
      }
    } else if (hit?.regionId != null && regions != null) {
      final capture = regions!.captureProfile(
        hit!.regionId!,
        sourceId: sourceId,
      );
      if (capture.reference != null) {
        if (_profiles.contains(capture.reference)) {
          _profiles.remove(capture.reference);
        } else {
          _profiles.add(capture.reference!);
        }
      } else {
        message =
            'This region cannot be identified uniquely (${capture.status.name}).';
      }
    }
    _refresh();
  }

  void selectEntity(SketchEntityId id, {bool additive = false}) => selectHit(
    SketchHit.entity(SketchHitKind.primitive, id),
    additive: additive,
  );

  void finishDrawing({double? dimension}) {
    if (!editable || anchor == null || preview == null) return;
    var end = preview!.position;
    final delta = end - anchor!;
    if (dimension != null) {
      if (!dimension.isFinite || dimension <= 0) {
        message = 'Enter a positive finite dimension.';
        notifyListeners();
        return;
      }
      end =
          anchor! +
          (delta.length == 0 ? Vector2(1, 0) : delta.normalized()) * dimension;
    }
    final length = (end - anchor!).length;
    if (length == 0 || !length.isFinite) {
      message = 'Choose a distinct endpoint or a positive radius.';
      notifyListeners();
      return;
    }
    final startId = _entityId(), endId = _entityId(), primitiveId = _entityId();
    final points = [
      ...definition!.points.values,
      SketchPoint(id: startId, x: anchor!.x, y: anchor!.y),
    ];
    final segments = [...definition!.segments.values];
    final circles = [...definition!.circles.values];
    final constraints = [...definition!.constraints.values];
    if (tool == SketchTool.line) {
      points.add(SketchPoint(id: endId, x: end.x, y: end.y));
      segments.add(
        SketchLineSegment(
          id: primitiveId,
          startPointId: startId,
          endPointId: endId,
        ),
      );
    } else {
      circles.add(
        SketchCircle(id: primitiveId, centerPointId: startId, radius: length),
      );
    }
    if (dimension != null) {
      constraints.add(
        SketchConstraint(
          id: _constraintId(),
          kind: tool == SketchTool.line
              ? SketchConstraintKind.lineLength
              : SketchConstraintKind.radius,
          references: [primitiveId],
          values: [dimension],
        ),
      );
    }
    _write(
      definition!.copyWith(
        points: points,
        segments: segments,
        circles: circles,
        constraints: constraints,
      ),
      tool == SketchTool.line ? 'Draw line' : 'Draw circle',
    );
    anchor = null;
    preview = null;
    interaction = tool == SketchTool.line
        ? SketchInteraction.lineStart
        : SketchInteraction.circleCenter;
    notifyListeners();
  }

  void beginDrag(SketchEntityId id, Vector2 origin) {
    if (!editable ||
        tool != SketchTool.select ||
        !{
          ...definition!.points.keys,
          ...definition!.segments.keys,
          ...definition!.circles.keys,
        }.contains(id)) {
      return;
    }
    _dragBefore = _solvedDefinition();
    _dragId = id;
    _dragOrigin = origin.clone();
    interaction = SketchInteraction.dragging;
    selected
      ..clear()
      ..add(id);
    selectedConstraint = null;
    _profiles.clear();
    document.beginTransaction('Drag sketch entity');
  }

  void updateDrag(Vector2 position) {
    if (interaction != SketchInteraction.dragging || _dragBefore == null) {
      return;
    }
    final before = _dragBefore!;
    final line = before.segments[_dragId];
    final circle = before.circles[_dragId];
    final ids = line != null
        ? {line.startPointId, line.endPointId}
        : circle != null
        ? {circle.centerPointId}
        : {_dragId!};
    final delta = position - _dragOrigin!;
    final result = const SketchSolver().solve(
      before,
      dragTargets: [
        for (final id in ids)
          SketchDragTarget(
            pointId: id,
            x: before.points[id]!.x + delta.x,
            y: before.points[id]!.y + delta.y,
          ),
      ],
    );
    dragDiagnostic = result.isValid ? null : result;
    if (result.isValid) {
      _write(
        before.copyWith(
          points: result.geometry!.points.values,
          circles: result.geometry!.circles.values,
        ),
        'Drag sketch entity',
      );
    } else {
      notifyListeners();
    }
  }

  void endDrag() {
    if (interaction != SketchInteraction.dragging) return;
    interaction = SketchInteraction.idle;
    _dragBefore = null;
    _dragId = null;
    _dragOrigin = null;
    document.commitTransaction();
  }

  void cancel() {
    final dragging = interaction == SketchInteraction.dragging;
    interaction = tool == SketchTool.line
        ? SketchInteraction.lineStart
        : tool == SketchTool.circle
        ? SketchInteraction.circleCenter
        : SketchInteraction.idle;
    anchor = null;
    preview = null;
    _dragBefore = null;
    _dragId = null;
    _dragOrigin = null;
    dragDiagnostic = null;
    message = null;
    if (dragging && document.hasActiveTransaction) document.cancelTransaction();
    notifyListeners();
  }

  void updateView(SketchView next) {
    view = next;
    notifyListeners();
  }

  void setSnapping(bool enabled) {
    snapping = enabled;
    preview = null;
    notifyListeners();
  }

  void showMessage(String text) {
    message = text;
    notifyListeners();
  }

  void undo() {
    cancel();
    selected.clear();
    selectedConstraint = null;
    document.undo();
  }

  void redo() {
    cancel();
    selected.clear();
    selectedConstraint = null;
    document.redo();
  }

  SketchDefinition _solvedDefinition() => definition!.copyWith(
    points: solution!.geometry!.points.values,
    circles: solution!.geometry!.circles.values,
  );
  void _write(SketchDefinition sketch, String label) => document.setFeature(
    SketchFeature.definition(id: activeId!, sketch: sketch),
    label: label,
  );

  void deleteSelection() {
    cancel();
    if (selectedConstraint != null) {
      removeConstraint(selectedConstraint!);
      selectedConstraint = null;
      return;
    }
    if (definition == null || selected.isEmpty) return;
    final removed = {...selected};
    for (final line in definition!.segments.values) {
      if (removed.contains(line.startPointId) ||
          removed.contains(line.endPointId)) {
        removed.add(line.id);
      }
    }
    for (final c in definition!.circles.values) {
      if (removed.contains(c.centerPointId)) removed.add(c.id);
    }
    final segments = definition!.segments.values
        .where((s) => !removed.contains(s.id))
        .toList();
    final circles = definition!.circles.values
        .where((c) => !removed.contains(c.id))
        .toList();
    final retainedPoints = {
      for (final s in segments) ...[s.startPointId, s.endPointId],
      for (final c in circles) c.centerPointId,
    };
    final formerlyUsed = {
      for (final s in definition!.segments.values) ...[
        s.startPointId,
        s.endPointId,
      ],
      for (final c in definition!.circles.values) c.centerPointId,
    };
    removed.addAll(formerlyUsed.difference(retainedPoints));
    final constraints = definition!.constraints.values
        .where((c) => !c.references.any(removed.contains))
        .toList();
    _write(
      definition!.copyWith(
        points: definition!.points.values.where((p) => !removed.contains(p.id)),
        segments: segments,
        circles: circles,
        constraints: constraints,
      ),
      'Delete sketch entities',
    );
    selected.clear();
    notifyListeners();
  }

  List<SketchConstraintKind> get availableConstraints {
    final d = definition;
    if (d == null) return [];
    final points = selected.where(d.points.containsKey).length;
    final lines = selected.where(d.segments.containsKey).length;
    final circles = selected.where(d.circles.containsKey).length;
    return [
      if (selected.length == 1 && lines == 1) ...[
        SketchConstraintKind.horizontal,
        SketchConstraintKind.vertical,
        SketchConstraintKind.lineLength,
      ],
      if (selected.length == 1 && circles == 1) ...[
        SketchConstraintKind.radius,
        SketchConstraintKind.diameter,
      ],
      if (selected.length == 1)
        points == 1
            ? SketchConstraintKind.fixedPoint
            : SketchConstraintKind.fixedPrimitive,
      if (selected.length == 2 && points == 2) ...[
        SketchConstraintKind.coincident,
        SketchConstraintKind.distance,
      ],
      if (selected.length == 2 && points == 1 && lines == 1)
        SketchConstraintKind.pointOnLine,
      if (selected.length == 2 && points == 1 && circles == 1)
        SketchConstraintKind.pointOnCircle,
      if (selected.length == 2 && lines == 2) ...[
        SketchConstraintKind.parallel,
        SketchConstraintKind.perpendicular,
        SketchConstraintKind.equalLengths,
      ],
      if (selected.length == 2 && circles == 2) SketchConstraintKind.equalRadii,
    ];
  }

  void addConstraint(SketchConstraintKind kind, {double? dimension}) {
    cancel();
    if (!availableConstraints.contains(kind)) return;
    try {
      final refs = selected.toList();
      if (kind == SketchConstraintKind.pointOnLine ||
          kind == SketchConstraintKind.pointOnCircle) {
        refs.sort((a, b) => definition!.points.containsKey(a) ? -1 : 1);
      }
      final values = <double>[];
      if (isDimension(kind)) {
        if (dimension == null) return;
        values.add(dimension);
      } else if (kind == SketchConstraintKind.fixedPoint) {
        final point =
            solution?.geometry?.points[refs.single] ??
            definition!.points[refs.single]!;
        values.addAll([point.x, point.y]);
      }
      final constraint = kind == SketchConstraintKind.fixedPrimitive
          ? SketchConstraint.fixPrimitive(
              id: _constraintId(),
              sketch: solution?.isValid == true
                  ? _solvedDefinition()
                  : definition!,
              primitiveId: refs.single,
            )
          : SketchConstraint(
              id: _constraintId(),
              kind: kind,
              references: refs,
              values: values,
            );
      _write(
        definition!.copyWith(
          constraints: [...definition!.constraints.values, constraint],
        ),
        'Add ${kind.name} constraint',
      );
    } on ArgumentError catch (e) {
      message = e.message.toString();
      notifyListeners();
    }
  }

  void editDimension(SketchConstraintId id, double value) {
    cancel();
    final previous = definition?.constraints[id];
    if (previous == null || !isDimension(previous.kind)) return;
    try {
      final updated = SketchConstraint(
        id: id,
        kind: previous.kind,
        references: previous.references,
        values: [value],
      );
      _write(
        definition!.copyWith(
          constraints: [
            for (final c in definition!.constraints.values)
              c.id == id ? updated : c,
          ],
        ),
        'Edit dimension',
      );
    } on ArgumentError catch (e) {
      message = e.message.toString();
      notifyListeners();
    }
  }

  void selectConstraint(SketchConstraintId id) {
    selectedConstraint = id;
    selected
      ..clear()
      ..addAll(definition?.constraints[id]?.references ?? []);
    notifyListeners();
  }

  void removeConstraint(SketchConstraintId id) {
    cancel();
    if (definition?.constraints.containsKey(id) != true) return;
    _write(
      definition!.copyWith(
        constraints: definition!.constraints.values.where((c) => c.id != id),
      ),
      'Remove constraint',
    );
  }

  static bool isDimension(SketchConstraintKind kind) => {
    SketchConstraintKind.lineLength,
    SketchConstraintKind.distance,
    SketchConstraintKind.radius,
    SketchConstraintKind.diameter,
  }.contains(kind);

  @override
  void dispose() {
    cancel();
    document.removeListener(_refresh);
    super.dispose();
  }
}
