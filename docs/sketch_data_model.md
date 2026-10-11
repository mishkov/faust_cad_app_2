# Independent sketch data and feature history

`lib/sketch/sketch.dart` exports the immutable authored sketch model. Headless constraints and solving are documented
in [Sketch constraints](sketch_constraints.md).
`SketchPoint` stores a stable `SketchEntityId` and finite local `x`/`y` values.
`SketchLineSegment` references two point IDs; `SketchCircle` references a center
point ID and has a finite positive radius. These entities are independent of
`Vertex`, `Edge`, `Wire`, `Face`, and all other `CadPrimitive` types. Coincident
points can have distinct identities, and multiple entities can share a point.

`SketchDefinition` associates these values with a `PlanarSupport`. It validates
unique IDs across all entity kinds and requires all segment/center references to
name existing points. Collections are immutable; vector access returns copies.
Zero-length segments are allowed as authored geometry and remain available for
the planar region engine to diagnose. Sketch validity does not require closed
profiles, bounded cells, or a position inside the support face's trim.

Callers assign IDs independently of entity order, coordinates, or topology.
Use `copyWith` for edits within the same sketch: retained IDs stay unchanged and
cannot switch entity kind, and deleted IDs enter the immutable `retiredIds` set.
New entities must receive fresh IDs. Removing a referenced point requires
removing or updating all of its consumers in the same edit. Encoding preserves
the reserved IDs; recreating a definition from scratch is for a new sketch, not
an edit that discards identity history. Undo can restore the same original entity
and its identity; it does not allocate a replacement entity.

## Document-owned authored values

Register `SketchFeature.evaluate` with `CadDocument` or `DocumentController`.
`SketchFeature.definition` stores the encoded entities and reserved IDs under the
`sketch` parameter key and puts their support in `FeatureDefinition.support`.
Face support automatically declares the producing feature as a dependency.
No mutable registry or evaluator closure holds essential sketch state.

```dart
final pointId = SketchEntityId('center');
final circleId = SketchEntityId('circle');
final sketchId = FeatureId('sketch');
final sketch = SketchDefinition(
  support: const PlanarSupport.principal(PrincipalPlane.xy),
  points: [SketchPoint(id: pointId, x: 0, y: 0)],
  circles: [
    SketchCircle(id: circleId, centerPointId: pointId, radius: 3),
  ],
);
final controller = DocumentController(
  evaluators: {SketchFeature.type: SketchFeature.evaluate},
  features: [SketchFeature.definition(id: sketchId, sketch: sketch)],
);
final authored = SketchFeature.readDefinition(controller.features.single);
final edited = authored.copyWith(
  circles: [SketchCircle(id: circleId, centerPointId: pointId, radius: 4)],
);
controller.updateParameters(
  sketchId,
  {SketchFeature.parameterKey: edited.toParameters()},
  label: 'Resize circle',
);
controller.undo();
controller.redo();
```

Parameter updates preserve the feature's support, references, and identity.
Use `setFeature(SketchFeature.definition(...))` to change the support and rebuild
its declared dependencies. Transaction previews, commit, cancellation, undo, and
redo use the existing controller machinery. Restoring definitions in a new
document reproduces the sketch without any external state. Finite malformed
authored parameters fail evaluation and remain undoable; unsupported mutable or
nonfinite parameter values are rejected before publication.

## Evaluation, references, and downstream inputs

The initial feature publishes one `FeatureOutput.sketch` with semantic key
`SketchFeature.outputKey` (`sketch`) and kind `OutputKind.sketch`. Its `data` is a
`SketchGeometry` containing the immutable definition and a captured resolved
`PlanarFrame`, plus separate solved coordinates and solve diagnostics. It
contains no derived topology or face boundary. Support edits
recompute placement and rebuild declared descendants while keeping entity IDs
and local coordinates. Principal planes use the existing axis conventions.

```dart
final reference = OutputReference(
  featureId: sketchId,
  key: SketchFeature.outputKey,
  kind: OutputKind.sketch,
);
final resolved = controller.evaluation.resolve(reference);
if (resolved.status == ReferenceStatus.resolved) {
  final data = resolved.output!.data as SketchGeometry;
  final inputs = const SketchPlanarAdapter().adaptSolved(data.solved);
  final regions = const PlanarRegionEngine().build(inputs);
  // Later operations explicitly consume regions and data.frame.
}
```

Downstream evaluators declare this reference in their feature inputs and consume
`context.input(name).data`; dependency output reads work identically. Resolution
uses feature ID, kind, and key with the existing resolved/missing/ambiguous/
unavailable statuses. Missing, ambiguous, failed, nonplanar, or singular-axis
attachments fail the sketch with `brokenAttachment`, remove its current outputs,
and block descendants. Last successful data remains only in diagnostic outputs.
Recovery rebuilds descendants without falling back to a principal plane.

`FeatureOutput.data` additionally captures finite scalar/list/string-keyed-map
values through the same deep-freezing rules as authored parameters. Mutable
objects are rejected. Sketch payloads have a dedicated immutable type; sharing
them across snapshots and consumers is safe. Frames and coordinate vectors are
defensive values. Existing topological constructors, body/face keys, geometry
copying, and rendering behavior remain intact. Reading `geometry` or calling
`materialize` on a non-topological output throws `StateError`; callers consume its
`data` instead. Topological outputs reject `data` access.

`EvaluationSnapshot.dataOutputs` exposes only valid current non-topological
outputs. `geometry` and `materializeGeometry` continue to export bodies only, so
sketches never enter solid tessellation, picking, or rendering automatically.

## Adapter and scope

`SketchPlanarAdapter.adapt` returns identified `PlanarSegment` and `PlanarCircle`
inputs in local coordinates. Segment direction follows its point references;
circle geometry remains analytic. Each input ID is the exact authored segment or
circle ID, preserving region boundary provenance across edits. Points supply
referenced coordinates and never create implicit boundaries. The adapter neither
builds topology nor selects regions. A later operation must explicitly use the
region engine and resolved frame before deriving CAD topology.

Tests cover identity and deletion rules, parameter validation, shared references,
adapter provenance, downstream region consumption, all principal planes,
translated/rotated/reversed face support, broken attachments and recovery,
body/face rendering preservation, mutation isolation, snapshots, undo/redo, and
transaction commit/cancellation. No sketch editor, disk persistence, or extrusion feature is introduced.
The headless constraint solver is documented separately.
