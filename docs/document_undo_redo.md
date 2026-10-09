# Document undo and redo

Task 5's feature history defines the model: stable feature IDs, definitions,
dependencies, and semantic input references. `DocumentController` records user
edits to that model. Undo/redo snapshots contain only ordered immutable
`FeatureDefinition` values. They do not store geometry or evaluator results.
Restoration calls `CadDocument.replaceFeatures`, using the same evaluator and
incremental invalidation as forward edits. Unchanged outputs can be reused;
changed definitions and descendants rebuild, exposing valid, failed, or blocked
states in `evaluation`. Evaluation revisions advance rather than rewind.

Create a controller with the same evaluator registry and initial definitions as
`CadDocument`. The controller owns its document and exposes read-only `features`
and `evaluation`, plus `ChangeNotifier` notifications. Route every user model
edit through it; do not maintain a separate mutable document. `canUndo`, `canRedo`,
`undoLabel`, and `redoLabel` are ready for later keyboard and toolbar actions.
Listeners see the complete model, evaluation, and history publication together.
Synchronous nested mutations from callbacks, evaluators, or listeners are rejected.

```dart
final controller = DocumentController(
  evaluators: {CubeFeature.type: CubeFeature.evaluate},
  features: initialFeatures,
);
controller.updateParameters(cubeId, {'size': 12}, label: 'Resize cube');
controller.undo();
controller.redo();
```

`addFeature` rejects duplicate IDs. `setFeature` adds or replaces a definition,
preserving its existing document position. `updateParameters` merges parameter
values while preserving type, ID, dependencies, and references. `removeFeature`
rejects unknown IDs and retains dependent definitions; their missing references
are diagnosed by the evaluator. `replaceFeatures` replaces the full ordered model.
IDs are caller-provided and never regenerated during restoration.

Group operations with `edit`. Its `DocumentEdit` draft is isolated from the live
document; the callback must return successfully before a single evaluation and
publication. A thrown command, duplicate ID, unknown edit target, or unsupported
parameter value leaves the document, evaluation, history, and notifications
unchanged. Captured drafts and caller-owned collections cannot mutate saved
states. Definitions recursively freeze their value parameters. A finite parameter
value that fails geometric evaluation (such as negative cube size) **is committed**
and undoable. Failed/blocked results, messages, and diagnostic outputs remain
available through `evaluation`; invalid geometry is excluded from current outputs.

```dart
controller.edit('Create assembly', (draft) {
  draft.updateParameters(cubeId, {'size': 12});
  draft.addFeature(dependentFeature);
});
```

Interactive edits use one explicit transaction. Each successful command inside
it publishes an evaluated preview but creates no individual history entry. The
transaction's label names its single committed entry. A rejected command leaves
the last accepted preview intact; the transaction can still commit or cancel.

```dart
controller.beginTransaction('Drag cube');
controller.updateParameters(cubeId, {'x': 10});
controller.updateParameters(cubeId, {'x': 20});
controller.commitTransaction(); // One entry for the entire drag.
// On gesture cancellation instead: controller.cancelTransaction();
```

Cancellation restores starting definitions through the evaluator and preserves
both history stacks. Undo/redo are disabled during a transaction and throw if
called; nested transactions and commit/cancel without a transaction also throw.
A new changed commit clears redo. Equal-value commands and empty or net-zero
transactions make no entries and preserve redo. A transaction commit requires
no extra evaluation because the final preview is already published.

`rebuild(ids)` refreshes external evaluator inputs without making an undo entry
or clearing redo. Undo, redo, and cancellation use current evaluator inputs,
rather than restoring old derived geometry. Evaluators should otherwise remain
deterministic functions of definitions and declared inputs.

Selection, camera position, navigation, and render settings belong outside this
controller and cannot become model undo entries. History is in memory and scoped
to one controller; dispose it with its owning UI. No sketch UI, keyboard bindings,
or full history panel is introduced here.
