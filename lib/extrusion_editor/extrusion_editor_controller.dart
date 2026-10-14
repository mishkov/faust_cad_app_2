import 'package:flutter/foundation.dart';

import '../document/document_controller.dart';
import '../document/feature_definition.dart';
import '../document/feature_id.dart';
import '../document/feature_result.dart';
import '../document/features/extrude_feature.dart';
import '../document/output_reference.dart';
import '../planar_regions/planar_regions.dart';
import '../sketch/sketch_geometry.dart';
import '../sketch/sketch_planar_adapter.dart';

final class ExtrusionEditorController extends ChangeNotifier {
  ExtrusionEditorController(this.document) {
    document.addListener(_refresh);
  }
  final DocumentController document;
  FeatureId? activeId;
  OutputReference? sketchReference;
  SketchGeometry? sketch;
  RegionResult? regions;
  String distanceText = '10';
  bool reverse = false;
  final List<ProfileReference> _profiles = [];
  Set<String> selectedRegionIds = {};
  List<String> diagnostics = [];
  int _serial = 0;

  bool get canConfirm =>
      activeId != null &&
      document.evaluation.features[activeId]?.state == FeatureState.valid;

  void create(FeatureId sketchId, {Iterable<String> regionIds = const []}) {
    if (activeId != null || document.hasActiveTransaction) {
      throw StateError('Finish the active edit first');
    }
    final ref = ExtrudeFeature.sketchReference(sketchId);
    sketchReference = ref;
    distanceText = '10';
    reverse = false;
    _profiles.clear();
    do {
      activeId = FeatureId('extrude-${++_serial}');
    } while (document.features.any((f) => f.id == activeId));
    _readSketch();
    for (final id in regionIds) {
      final capture = regions?.captureProfile(
        id,
        sourceId: ExtrudeFeature.sourceId(ref),
      );
      if (capture?.reference != null) _profiles.add(capture!.reference!);
    }
    document.beginTransaction('Create extrusion');
    _publish();
  }

  void open(FeatureId id) {
    if (activeId != null || document.hasActiveTransaction) {
      throw StateError('Finish the active edit first');
    }
    final feature = document.features.firstWhere((f) => f.id == id);
    if (feature.type != ExtrudeFeature.type) {
      throw ArgumentError('Not an extrusion');
    }
    activeId = id;
    sketchReference = feature.inputs[ExtrudeFeature.inputKey];
    distanceText = '${feature.parameters['distance']}';
    reverse = feature.parameters['reverse'] == true;
    _profiles.clear();
    final stored = feature.parameters[ExtrudeFeature.profilesKey];
    if (stored is Map<String, Object?>) {
      try {
        _profiles.addAll(ProfileSelectionReference.fromJson(stored).references);
      } on FormatException {
        // Keep malformed selections editable through clear/reselect.
      } on ArgumentError {
        // Mixed or empty selections have no recoverable profile values.
      }
    }
    document.beginTransaction('Edit extrusion');
    _refresh();
  }

  void _readSketch() {
    final data = sketchReference == null
        ? null
        : document.evaluation.resolve(sketchReference!).output?.data;
    sketch = data is SketchGeometry ? data : null;
    regions = sketch == null
        ? null
        : const PlanarRegionEngine().build(
            const SketchPlanarAdapter().adaptSolved(sketch!.solved),
          );
  }

  void _refresh() {
    if (activeId == null) return;
    _readSketch();
    selectedRegionIds = {};
    diagnostics = [];
    if (sketch == null) {
      final upstream = document.evaluation.features[sketchReference?.featureId];
      diagnostics.add(
        'Sketch is unavailable. ${upstream?.message ?? 'Restore its support or sketch output.'}',
      );
    }
    for (final profile in _profiles) {
      final resolved = regions?.resolveProfile(
        profile,
        sourceId: ExtrudeFeature.sourceId(sketchReference!),
      );
      if (resolved?.status == RegionResolutionStatus.resolved) {
        selectedRegionIds.add(resolved!.candidates.single.id);
      } else {
        diagnostics.add(
          'Selected profile is ${resolved?.status.name ?? 'unavailable'}. Restore its boundary or clear and reselect.',
        );
      }
    }
    diagnostics.addAll(regions?.diagnostics.map((d) => d.message) ?? []);
    final result = document.evaluation.features[activeId];
    if (result?.state != FeatureState.valid && result?.message != null) {
      diagnostics.add(result!.message!);
    }
    notifyListeners();
  }

  void toggleRegion(String id) {
    if (activeId == null || regions == null || sketchReference == null) return;
    final capture = regions!.captureProfile(
      id,
      sourceId: ExtrudeFeature.sourceId(sketchReference!),
    );
    if (capture.reference == null) {
      diagnostics.add(
        'This region cannot be identified uniquely (${capture.status.name}). Select another region.',
      );
      notifyListeners();
      return;
    }
    if (_profiles.contains(capture.reference)) {
      _profiles.remove(capture.reference);
    } else {
      _profiles.add(capture.reference!);
    }
    _publish();
  }

  void clearSelection() {
    _profiles.clear();
    _publish();
  }

  void setDistance(String text) {
    distanceText = text;
    _publish();
  }

  void setReverse(bool value) {
    reverse = value;
    _publish();
  }

  void _publish() {
    if (activeId == null) return;
    final parsed = double.tryParse(distanceText);
    document.setFeature(
      FeatureDefinition(
        id: activeId!,
        type: ExtrudeFeature.type,
        inputs: {ExtrudeFeature.inputKey: ?sketchReference},
        parameters: {
          ExtrudeFeature.profilesKey: _profiles.isEmpty
              ? {'version': 1, 'profiles': <Object?>[]}
              : ProfileSelectionReference(_profiles).toJson(),
          'distance': parsed != null && parsed.isFinite && parsed > 0
              ? parsed
              : 0.0,
          'reverse': reverse,
        },
      ),
    );
    _refresh();
  }

  bool confirm() {
    if (!canConfirm) return false;
    activeId = null;
    document.commitTransaction();
    notifyListeners();
    return true;
  }

  void cancel() {
    if (activeId == null) return;
    activeId = null;
    document.cancelTransaction();
    notifyListeners();
  }

  @override
  void dispose() {
    document.removeListener(_refresh);
    cancel();
    super.dispose();
  }
}
