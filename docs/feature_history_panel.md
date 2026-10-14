# CAD feature-history panel

The panel builds on Task 14's linked extrusion workflow (PR #30), available on
main. It lists `DocumentController.features` in authored order. The evaluator's
`evaluationOrder` remains its separate dependency traversal; editing an earlier
feature replaces it in place. Each row shows a readable name, type, dependencies,
and valid/failed/blocked state. Selecting a row reveals its stable ID, named
inputs/support, Rename, and Delete. Valid bodies can be highlighted in the
viewport, and viewport picking also selects their producing history item.

Feature names are optional definition metadata, separate from ID and parameters.
Unnamed features display their readable type and ID. Names can repeat; references
always use feature IDs and semantic output keys. Rename trims whitespace and
rejects blank names. It is one ordinary document edit, and both editors preserve
names, support, dependencies, and inputs when changing parameters.

Sketch rows reopen the existing sketch editor or start an extrusion. Extrusion
rows reopen the existing distance/reverse/profile editor. Its previews rebuild
through the controller, Confirm records one edit, and Cancel restores the starting
model. Sketch editing, including early constraints or geometry, uses the same
controller and dependency invalidation. Document notifications publish a complete
evaluation, then the CAD screen materializes current valid geometry and updates
its viewport revision. Failed/blocked outputs and last-good diagnostic geometry
are excluded from rendering and picking. Independent valid features stay usable.

Failures appear at their affected row, including missing/ambiguous profile
messages, unavailable inputs, and broken attachments. Long evaluator messages
are displayed in four lines with the full diagnostic available in a tooltip.
Selected attachment/input labels use producer names and semantic roles (such as
End cap) rather than displaying an entire encoded extrusion boundary signature.
No nearest-profile, face-index, or silent reference replacement is added.

## Deletion contract

Delete opens a confirmation listing every direct and transitive dependent, in
its authored order. The list follows document publications while the dialog is
open. Only the chosen feature is removed. Dependents keep their definitions,
IDs, parameters, profile references, and attachments. Missing producers cause
failed references; their descendants become failed attachments or blocked
features according to the existing evaluator. These items stay in the panel.
Undo restores the deleted definition in its original place and reevaluates its
chain. Redo repeats the deletion. There is no cascading deletion.

Automatically created IDs are allocated by the document controller and reserved
for its lifetime, including after deletion, undo, or cancellation. Recreating an
editor cannot reuse such an ID and accidentally reconnect surviving references
to a different feature. The reservation bookkeeping is outside model undo/redo.
Explicit definition restoration still uses the original IDs.

## Undo and navigation

The separate Model edits toolbar and existing keyboard shortcuts operate the
controller's undo/redo stacks. The feature list is model history, not a command
log. Row selection, picking, camera motion, and editor reopening do not append
model undo entries. Rename and Delete each append one; extrusion changes commit
one transaction; sketch edits retain the existing controller grouping behavior.
Removing the selected feature clears its transient selection. Undo restores the
model without restoring camera or selection state.

This task adds no history reordering, suppression, rollback markers, disk
persistence, or general repair tools.

## Verification

`test/feature_history/` verifies a branched chain of three extrusions and two
attached sketches, an independent cube, authored/dependency order separation,
coherent publications and viewport refresh, real sketch drags, distance/reverse,
retained dependents on deletion, missing profile and attachment failures, and
undo/redo of definitions, references, analytic volumes, and support frames.
The ambiguity UI test supplies a structured evaluator failure to verify display;
the existing region/reference tests verify actual conservative ambiguity
resolution. ID reservation tests cover deletion, undo, canceled extrusions, and
recreated editors. Existing editor tests wait for history-list scrolling before
interacting with newly offscreen actions.

Interactive previews in `lib/feature_history/feature_history_preview.dart`
provide valid linked features and a Remove base boundary action to inspect
failed/blocked rows and recover using Undo, at desktop and compact sizes.

```sh
flutter test
flutter analyze
flutter run -d macos --enable-impeller
```
