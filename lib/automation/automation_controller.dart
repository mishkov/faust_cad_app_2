import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../document/document_controller.dart';
import '../document/feature_definition.dart';
import '../document/feature_evaluation_failure.dart';
import '../document/feature_id.dart';
import '../document/features/extrude_feature.dart';
import '../document/features/sketch_feature.dart';
import '../document/planar_support.dart';
import '../planar_regions/planar_regions.dart';
import '../sketch/sketch_definition.dart';
import '../sketch/sketch_geometry.dart';
import '../sketch/sketch_planar_adapter.dart';
import 'automation_tools.dart';

/// Owns revocable AI editing of the visible document.
final class AutomationController extends ChangeNotifier {
  AutomationController(
    this.document, {
    this.canBegin,
    this.render,
    this.leaseDuration = const Duration(minutes: 5),
  });

  final DocumentController document;
  final bool Function()? canBegin;
  final Future<Map<String, Object?>> Function(Map<String, Object?>)? render;
  final Duration leaseDuration;
  Object? _owner;
  String? _connection;
  String? _session;
  Timer? _lease;
  bool _busy = false;
  bool _disposed = false;
  bool paused = false;
  String? operation;
  final _receipts =
      <String, ({String fingerprint, Map<String, Object?> result})>{};

  bool get isActive => _owner != null;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void enable() {
    paused = false;
    notifyListeners();
  }

  void stop({bool pause = true}) {
    paused = pause;
    _lease?.cancel();
    final owner = _owner;
    _owner = null;
    _session = null;
    _connection = null;
    operation = null;
    if (owner != null) document.releaseEditLock(owner);
    notifyListeners();
  }

  void disconnect(String connection) {
    if (_connection == connection) stop(pause: false);
  }

  Map<String, Object?> inspect() => {
    'units': 'mm',
    'angleUnits': 'degrees',
    'revision': document.evaluation.revision,
    'aiActive': isActive,
    'aiPaused': paused,
    'undoCount': document.undoCount,
    'redoCount': document.redoCount,
    'undoLabel': document.undoLabel,
    'redoLabel': document.redoLabel,
    'features': [
      for (final f in document.features)
        {
          'id': f.id.value,
          'name': f.name,
          'type': f.type,
          'parameters': f.parameters,
          'plane': f.support?.principalPlane?.name,
          'dependencies': f.dependencies.map((id) => id.value).toList(),
          'inputs': {
            for (final input in f.inputs.entries)
              input.key: {
                'featureId': input.value.featureId.value,
                'key': input.value.key,
                'kind': input.value.kind.name,
              },
          },
          'state': document.evaluation.features[f.id]?.state.name,
          'message': document.evaluation.features[f.id]?.message,
          'outputs': [
            for (final o in document.evaluation.features[f.id]!.outputs)
              {'key': o.key, 'kind': o.kind.name},
          ],
        },
    ],
  };

  Future<Map<String, Object?>> call(
    String connection,
    String name,
    Map<String, Object?> args,
  ) async {
    try {
      validateAutomationArguments(name, args);
      if (name == 'cad_get_document') return _ok(inspect());
      if (name == 'cad_begin') {
        if (paused) {
          throw StateError('AI was stopped. Re-enable it in the app.');
        }
        if (isActive ||
            _busy ||
            document.hasActiveTransaction ||
            canBegin?.call() == false) {
          throw StateError('Finish the current edit or AI session first.');
        }
        final owner = Object();
        document.acquireEditLock(owner);
        _owner = owner;
        _connection = connection;
        _session = List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        _receipts.clear();
        _renewLease();
        notifyListeners();
        return _ok({
          'sessionId': _session,
          'revision': document.evaluation.revision,
          'units': 'mm',
        });
      }
      if (name == 'cad_get_profiles') {
        final revision = document.evaluation.revision;
        final regions = await _regions(args['sketchId'] as String);
        return _ok({
          'revision': revision,
          'regions': [
            for (final r in regions.regions)
              {'id': r.id, 'area': r.area, 'holeCount': r.holes.length},
          ],
        });
      }
      if (name == 'cad_render') {
        if (render == null) {
          throw StateError('Inspection rendering is unavailable.');
        }
        return await render!(args);
      }
      final owner = _owner;
      if (owner == null ||
          args['sessionId'] != _session ||
          connection != _connection) {
        throw StateError(
          'Session expired or revoked. No model changes were made.',
        );
      }
      _renewLease();
      if (name == 'cad_finish') {
        stop(pause: false);
        return _ok(inspect());
      }
      final requestId = args['requestId'] as String;
      final fingerprint = jsonEncode(
        _canonical({'name': name, 'arguments': args}),
      );
      final receipt = _receipts[requestId];
      if (receipt != null) {
        if (receipt.fingerprint != fingerprint) {
          throw StateError(
            'requestId was already used with different arguments.',
          );
        }
        return receipt.result;
      }
      if (_receipts.length >= 512) {
        throw StateError(
          'Session operation limit reached. Finish this session.',
        );
      }
      if (_busy) throw StateError('Another modeling operation is running.');
      if (args['expectedRevision'] != document.evaluation.revision) {
        throw StateError(
          'Revision changed. Inspect the document/profiles before retrying.',
        );
      }
      _busy = true;
      operation = name;
      notifyListeners();
      Map<String, Object?> result;
      try {
        if (name == 'cad_undo' || name == 'cad_redo') {
          await document.restoreHistory(redo: name == 'cad_redo', owner: owner);
        } else if (name == 'cad_delete_feature') {
          final id = FeatureId(args['featureId'] as String);
          if (!document.features.any((f) => f.id == id)) {
            throw ArgumentError('Missing feature: $id');
          }
          await document.editValidated(
            'Delete feature',
            document.features.where((f) => f.id != id).toList(),
            owner: owner,
          );
        } else {
          final feature = await _feature(name, args);
          if (document.features.length >= 64 &&
              !document.features.any((f) => f.id == feature.id)) {
            throw StateError('Document feature limit (64) reached.');
          }
          final exists = document.features.any((f) => f.id == feature.id);
          await document.editValidated(
            '${exists ? 'Edit' : 'Create'} ${feature.name ?? feature.type}',
            [
              for (final f in document.features)
                f.id == feature.id ? feature : f,
              if (!exists) feature,
            ],
            owner: owner,
          );
        }
        result = _ok(inspect());
      } catch (error) {
        result = _error(error);
      } finally {
        _busy = false;
        operation = null;
        notifyListeners();
      }
      if (identical(owner, _owner)) {
        _receipts[requestId] = (fingerprint: fingerprint, result: result);
      }
      return result;
    } catch (error) {
      return _error(error);
    }
  }

  Future<FeatureDefinition> _feature(
    String name,
    Map<String, Object?> args,
  ) async {
    final id = FeatureId(args['featureId'] as String);
    final existing = document.features.where((f) => f.id == id).firstOrNull;
    if (name == 'cad_set_sketch') {
      if (existing != null && existing.type != SketchFeature.type) {
        throw ArgumentError('Feature ID belongs to another type.');
      }
      final support = PlanarSupport.principal(
        PrincipalPlane.values.byName(args['plane'] as String),
      );
      var sketch = SketchDefinition.fromParameters(
        support: support,
        parameters: {
          'version': 2,
          'points': args['points'],
          'segments': args['segments'],
          'circles': args['circles'],
          'constraints': [],
          'retiredIds': [],
          'retiredConstraintIds': [],
        },
      );
      if (existing != null) {
        final authored = SketchFeature.readDefinition(existing);
        sketch = authored.copyWith(
          support: support,
          points: sketch.points.values,
          segments: sketch.segments.values,
          circles: sketch.circles.values,
        );
      }
      final definition = SketchFeature.definition(id: id, sketch: sketch);
      return FeatureDefinition(
        id: id,
        type: definition.type,
        name: args['name'] as String? ?? existing?.name,
        support: definition.support,
        parameters: definition.parameters,
      );
    }
    if (name == 'cad_extrude') {
      if (existing != null) {
        throw ArgumentError(
          'Extrusion ID already exists. Use cad_set_extrusion.',
        );
      }
      final sketchId = FeatureId(args['sketchId'] as String);
      final regions = await _regions(sketchId.value);
      final reference = ExtrudeFeature.sketchReference(sketchId);
      final profiles = <ProfileReference>[];
      for (final regionId in args['regionIds'] as List) {
        final capture = regions.captureProfile(
          regionId as String,
          sourceId: ExtrudeFeature.sourceId(reference),
        );
        if (capture.reference == null) {
          throw ArgumentError('Profile $regionId is missing or ambiguous.');
        }
        profiles.add(capture.reference!);
      }
      final definition = ExtrudeFeature.definition(
        id: id,
        sketch: reference,
        profiles: ProfileSelectionReference(profiles),
        distance: (args['distance'] as num).toDouble(),
        reverse: args['reverse'] == true,
      );
      return FeatureDefinition(
        id: id,
        type: definition.type,
        name: args['name'] as String?,
        parameters: definition.parameters,
        inputs: definition.inputs,
      );
    }
    if (name == 'cad_set_extrusion') {
      if (existing?.type != ExtrudeFeature.type) {
        throw ArgumentError('Missing extrusion.');
      }
      return FeatureDefinition(
        id: id,
        type: existing!.type,
        name: existing.name,
        parameters: {
          ...existing.parameters,
          'distance': args['distance'],
          'reverse': args['reverse'] ?? existing.parameters['reverse'],
        },
        inputs: existing.inputs,
        support: existing.support,
        dependencies: existing.dependencies,
      );
    }
    throw ArgumentError('Unknown modeling operation: $name');
  }

  Future<RegionResult> _regions(String id) async {
    final output = document.evaluation
        .resolve(ExtrudeFeature.sketchReference(FeatureId(id)))
        .output
        ?.data;
    if (output is! SketchGeometry) {
      throw ArgumentError('Sketch is unavailable: $id');
    }
    final result = await compute(_buildRegions, output);
    if (!result.isValid) {
      throw StateError(
        'Invalid sketch regions: ${result.diagnostics.map((d) => d.message).join('; ')}',
      );
    }
    return result;
  }

  void _renewLease() {
    _lease?.cancel();
    _lease = Timer(leaseDuration, () => stop(pause: false));
  }

  Map<String, Object?> _ok(Map<String, Object?> data) => {
    'content': [
      {'type': 'text', 'text': jsonEncode(data)},
    ],
    'structuredContent': data,
  };

  Map<String, Object?> _error(Object error) => {
    'isError': true,
    'content': [
      {
        'type': 'text',
        'text': jsonEncode({
          'error': error.toString(),
          'revision': document.evaluation.revision,
          if (error is FeatureEvaluationFailure)
            'diagnostics': error.diagnostics,
        }),
      },
    ],
  };

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}

RegionResult _buildRegions(SketchGeometry sketch) => const PlanarRegionEngine()
    .build(const SketchPlanarAdapter().adaptSolved(sketch.solved));

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}
