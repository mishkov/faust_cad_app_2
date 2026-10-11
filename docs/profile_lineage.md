# Persistent profile selection and extrusion lineage

Task 10's sketch entities and `SketchPlanarAdapter`, the region/extrusion engines,
and the document output/planar-support foundation are merged on main. This layer
adds stored selection values and an output adapter. It adds no editor behavior or
production `ExtrudeFeature`.

## Capture, store, and rebuild

`RegionResult.captureProfile` returns a `ProfileCapture`. Only a uniquely
identifiable cell publishes a `ProfileReference`. Use a stable `sourceId` scoped
to the producing sketch feature/output and preserve it on every rebuild. Entity
IDs must be unique in that scope and never reused for unrelated geometry.
`SketchPlanarAdapter` retains Task 10's authored segment/circle IDs after solving.

```dart
final capture = arrangement.captureProfile(cell.id, sourceId: sketchSourceId);
if (capture.status != RegionResolutionStatus.resolved) return;
final selection = ProfileSelectionReference([capture.reference!]);
final stored = selection.toJson(); // Suitable for FeatureDefinition.parameters.
final restored = ProfileSelectionReference.fromJson(stored);
final current = rebuiltArrangement.resolveProfiles(
  restored,
  sourceId: sketchSourceId,
);
if (current.status != RegionResolutionStatus.resolved) {
  // Report the failure and retain the reference; never choose another region.
  return;
}
final result = const AnalyticExtrusionService().extrude(
  regions: rebuiltArrangement,
  regionIds: current.regions.map((r) => r.id),
  frame: resolvedSketchFrame,
  distance: 5,
);
```

Selection values are immutable, nonempty, canonical, and scoped to one producer.
Duplicate references are idempotent. JSON schemas are versioned; unsupported or
malformed data throws during decoding. `toJson` returns independent finite value
data. There are no arrangement owners, topology, vectors, or `region:N`/`union:N`
IDs in these values. Resolution exposes current cells and material only if every
reference resolves and their union is manifold. It never drops a missing cell.
Per-cell resolutions retain all ambiguous candidates; point-connected material
is unavailable.

## Identity rules

Arrangement vertices record authored segment start/end events and intersection
events. Each intersection event contains the sorted source pair and the sign of
the crossing between authored tangents. Circle tangents run counterclockwise.
The two crossings of a circle pair or a line/circle pair have opposite signs;
tangent/collinear contacts use zero. Circle branches are labeled by intersection
construction, rather than rounded coordinates or parameter values. Shared
junctions collect every incident event, including coincident source aliases.

A semantic boundary span contains curve kind, every source ID and traversal
direction, and its start/end junction events. Adjacent patches with the same
source directions join across synthetic circle seams. A circle without authored
junctions is one closed span. Cell signatures canonicalize cyclic outer traversal
and sort canonical hole traversals. Loop start positions, hole order, input
order, and patch counts are excluded. Coordinates and numeric parameter values
are excluded; interval signs encode only authored traversal direction.

The lens of overlapping circles traverses both sources positively; each crescent
reverses its inner-facing span. Crossing labels distinguish the paths between
intersections. These identities remain distinct after ordinary center/radius
edits and rotation across seams when directed boundary relationships persist.
Disks, annuli, rectangles, and line/circle cells follow the same contract.

| Outcome | Meaning |
| --- | --- |
| `resolved` | Exactly one current cell has the complete stored lineage. |
| `missing` | No cell matches, or its producer scope differs. Splitting, merging, deletion, changed holes, or reversed authored segment endpoints can retire a reference. |
| `ambiguous` | Several cells match; every candidate is returned, none is selected. |
| `unavailable` | Numerical failure or absent supported boundary correspondence. |

Capture checks uniqueness even in the original snapshot. The existing
`RegionReference` remains operation-level provenance with conservative source-set
matching; it is not a stored selection or a fallback.

## Extrusion outputs and attachment

`ExtrusionLineageAdapter` assigns semantic document outputs to a result:

```dart
final lineage = const ExtrusionLineageAdapter().adapt(
  featureId: extrusionFeatureId,
  profileSourceId: sketchSourceId,
  extrusion: result,
);
// Publish lineage.outputs only after checking result.isValid.
final resolution = lineage.resolve(previousFaceReference);
```

Bodies use complete union-component boundary lineage. Caps add the authored
`startCap`/`endCap` role. Distance and reverse changes preserve these roles.
Unrelated component addition, removal, split, or merge preserves identifiable
unaffected body/cap names even when local indices change. A changed component
boundary retires its body/cap names.

Wall names use the directed semantic span independently of component identity.
An unchanged wall can survive a component split even when body/caps are retired.
Cancelled internal boundaries have no wall; holes retain opposite material-side
traversal. The adapter maps exact current portion provenance to spans, but these
object lookups never become stored names.

Several analytic face patches for one wall span do not identify an individual
attachable face. The adapter records their semantic name and candidate count in
`ambiguousKeys`, lists the faces in `unavailableFaces`, and publishes no face
outputs or attachment keys for those patches. Full-circle walls normally have
two half-cylinder patches and remain in this category. When an initially single
wall patch crosses an artificial seam on rebuild, its former face reference is
ambiguous; it never moves to an arbitrary half. Body and cap names survive.
Tessellation and arbitrary patch indices never enter identity.

`lineage.resolve` reports missing, ambiguous, or unavailable explicitly. Invalid
extrusion results are unavailable. Absent correspondence sets
`hasUnsupportedCorrespondence`, so unknown names cannot be guessed. Only unique,
justified `FeatureOutput` values and body face keys reach `EvaluationSnapshot`.
Withheld ambiguous faces cannot be picked or attached. A former attachment to a
now-ambiguous face is absent in the new snapshot and breaks; the adapter retains
the detailed ambiguity diagnosis. Output capture copies topology and preserves
named-face correspondence within each body.

## Limits and verification

This is conservative supported line/circle correspondence, not general
topological naming. Added intersections can retire union names even if their
silhouette stays unchanged, because boundary relationships changed. Unsupported
curves, arbitrary Boolean histories, fusion with existing solids, and identities
for arbitrary analytic patches need more authored semantics. Restoring earlier
authored relationships, including undo, can resolve earlier references again.

Tests cover JSON/document storage, disks/annuli, lens/crescents, line/circle
crossings, rectangle edits, permutation, disconnected components, splits/merges,
deletion, ambiguity, unavailable correspondence, invalid arrangements,
non-manifold material, arc subdivision, distance/reverse/frame changes, named
face publication, and topology isolation. A test-only evaluator consumes Task 10
sketch outputs and stored selection, publishes adapted extrusion, rebuilds a
face-attached sketch, and verifies broken-reference handling and document undo.

Run `flutter test` and `flutter analyze` from the worktree root.
