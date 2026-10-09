import 'package:flutter/foundation.dart';

import 'cad_document.dart';
import 'document_edit.dart';
import 'evaluation_snapshot.dart';
import 'feature_definition.dart';
import 'feature_evaluation_context.dart';
import 'feature_id.dart';

/// Document model edits and undo/redo state for future UI actions.
///
/// Owns the mutable document so all user edits pass through this API. History
/// stores immutable definitions, never derived geometry, selection, or camera
/// state. Restoration uses the same dependency evaluator as normal edits.
final class DocumentController extends ChangeNotifier {
  DocumentController({
    required Map<String, FeatureEvaluator> evaluators,
    List<FeatureDefinition> features = const [],
  }) : _document = CadDocument(evaluators: evaluators, features: features);

  final CadDocument _document;
  final List<_UndoEntry> _undo = [];
  final List<_UndoEntry> _redo = [];
  ({String label, List<FeatureDefinition> before})? _transaction;
  bool _busy = false;
  bool _disposed = false;

  /// The current immutable model definitions, including transaction previews.
  List<FeatureDefinition> get features => _document.features;

  /// The latest evaluated outputs and failed or blocked feature diagnostics.
  EvaluationSnapshot get evaluation => _document.evaluation;

  /// Whether an interactive edit is awaiting commit or cancellation.
  bool get hasActiveTransaction => _transaction != null;

  /// Whether an undo action is currently available.
  bool get canUndo => !hasActiveTransaction && _undo.isNotEmpty;

  /// Whether a redo action is currently available.
  bool get canRedo => !hasActiveTransaction && _redo.isNotEmpty;

  /// The number of committed edits available to undo.
  int get undoCount => _undo.length;

  /// The number of undone edits available to redo.
  int get redoCount => _redo.length;

  /// The label for the available undo action, or `null`.
  String? get undoLabel => canUndo ? _undo.last.label : null;

  /// The label for the available redo action, or `null`.
  String? get redoLabel => canRedo ? _redo.last.label : null;

  /// Applies a grouped command atomically and reports whether it changed values.
  ///
  /// Runs [change] synchronously on an isolated draft. If it throws, definitions,
  /// evaluation, and history remain unchanged. Successful changes evaluate once
  /// and become one undo entry, or a preview within the active transaction.
  /// Evaluation
  /// failures still publish the accepted definitions and remain undoable.
  /// Equal definitions in the same order create no entry and preserve redo.
  bool edit(String label, void Function(DocumentEdit draft) change) => _run(() {
    final before = features;
    final draft = DocumentEdit(before);
    change(draft);
    final after = draft.features;
    if (listEquals(before, after)) return false;
    _document.replaceFeatures(after);
    if (!hasActiveTransaction) _record(label, before, after);
    notifyListeners();
    return true;
  });

  /// Adds a feature as one edit, rejecting an existing ID.
  bool addFeature(FeatureDefinition feature, {String label = 'Add feature'}) =>
      edit(label, (draft) => draft.addFeature(feature));

  /// Adds or replaces a feature as one edit.
  bool setFeature(FeatureDefinition feature, {String label = 'Set feature'}) =>
      edit(label, (draft) => draft.setFeature(feature));

  /// Removes a feature as one edit, retaining dependent definitions.
  bool removeFeature(FeatureId id, {String label = 'Remove feature'}) =>
      edit(label, (draft) => draft.removeFeature(id));

  /// Changes parameters as one edit without changing references or identity.
  bool updateParameters(
    FeatureId id,
    Map<String, Object?> values, {
    String label = 'Change parameters',
  }) => edit(label, (draft) => draft.updateParameters(id, values));

  /// Replaces all definitions as one edit.
  bool replaceFeatures(
    List<FeatureDefinition> features, {
    String label = 'Replace features',
  }) => edit(label, (draft) => draft.replaceFeatures(features));

  /// Starts coalescing evaluated previews into a single labeled undo entry.
  ///
  /// Undo and redo are disabled until [commitTransaction] or
  /// [cancelTransaction]. Nested transactions throw a [StateError].
  void beginTransaction(String label) => _run(() {
    if (hasActiveTransaction) {
      throw StateError('A transaction is already active');
    }
    _transaction = (label: label, before: features);
    notifyListeners();
  });

  /// Commits the net transaction change and reports whether it made an entry.
  ///
  /// Redo is cleared only for a changed commit. A transaction that returns to
  /// its starting definitions makes no entry and preserves redo.
  bool commitTransaction() => _run(() {
    final transaction = _requireTransaction();
    final after = features;
    final changed = !listEquals(transaction.before, after);
    if (changed) _record(transaction.label, transaction.before, after);
    _transaction = null;
    notifyListeners();
    return changed;
  });

  /// Restores the starting definitions through the evaluator and preserves redo.
  void cancelTransaction() => _run(() {
    final transaction = _requireTransaction();
    if (!listEquals(transaction.before, features)) {
      _document.replaceFeatures(transaction.before);
    }
    _transaction = null;
    notifyListeners();
  });

  /// Restores the previous model through the evaluator, if available.
  ///
  /// Throws a [StateError] during a transaction; otherwise returns `false` if
  /// there is no undo entry. Moves history only after successful publication.
  bool undo() => _run(() {
    _requireNoTransaction();
    if (_undo.isEmpty) return false;
    final entry = _undo.last;
    _document.replaceFeatures(entry.before);
    _undo.removeLast();
    _redo.add(entry);
    notifyListeners();
    return true;
  });

  /// Restores the next model through the evaluator, if available.
  ///
  /// Throws a [StateError] during a transaction; otherwise returns `false` if
  /// there is no redo entry.
  bool redo() => _run(() {
    _requireNoTransaction();
    if (_redo.isEmpty) return false;
    final entry = _redo.last;
    _document.replaceFeatures(entry.after);
    _redo.removeLast();
    _undo.add(entry);
    notifyListeners();
    return true;
  });

  /// Rebuilds external evaluator inputs without recording a model edit.
  ///
  /// Does not change definitions or clear redo. Derived outputs are always
  /// evaluated from current inputs, including after undo, redo, or cancellation.
  EvaluationSnapshot rebuild(Set<FeatureId> ids) => _run(() {
    final result = _document.rebuild(ids);
    notifyListeners();
    return result;
  });

  void _record(
    String label,
    List<FeatureDefinition> before,
    List<FeatureDefinition> after,
  ) {
    _undo.add((label: label, before: before, after: after));
    _redo.clear();
  }

  ({String label, List<FeatureDefinition> before}) _requireTransaction() =>
      _transaction ?? (throw StateError('No transaction is active'));

  void _requireNoTransaction() {
    if (hasActiveTransaction) {
      throw StateError('Finish the active transaction first');
    }
  }

  T _run<T>(T Function() action) {
    if (_disposed) throw StateError('Document controller is disposed');
    if (_busy) throw StateError('Document edits are not reentrant');
    _busy = true;
    try {
      return action();
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    if (_busy) throw StateError('Cannot dispose during a document edit');
    _disposed = true;
    _undo.clear();
    _redo.clear();
    _transaction = null;
    super.dispose();
  }
}

typedef _UndoEntry = ({
  String label,
  List<FeatureDefinition> before,
  List<FeatureDefinition> after,
});
