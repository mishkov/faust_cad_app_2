# Headless analytic extrusion

`lib/extrusion/extrusion.dart` exports `AnalyticExtrusionService` and its result
and provenance types. It depends on the planar frames, circular boundaries,
cylindrical surfaces (tasks 1–3), and planar region engine (task 7) already merged
on main. It does not depend on scene state, sketch entities, constraints, UI, or
feature evaluation.

```dart
final arrangement = const PlanarRegionEngine().build([
  PlanarCircle(id: 'outer', center: Vector2.zero(), radius: 3),
  PlanarCircle(id: 'inner', center: Vector2.zero(), radius: 1),
]);
final annulus = arrangement.regions.singleWhere((r) => r.holes.isNotEmpty);
final result = const AnalyticExtrusionService().extrude(
  regions: arrangement,
  regionIds: [annulus.id],
  frame: PlanarFrame.xz(origin: Vector3(10, 20, 30)),
  distance: 5,
  reverse: false,
);
if (result.isValid) {
  final Solid body = result.solids.single;
  final caps = result.volumes.single.faces.where(
    (f) => f.role != ExtrusionFaceRole.wall,
  );
}
```

The service accepts IDs of validated atomic cells from **one** `RegionResult`.
Independent profile boundaries must first be built in the same arrangement;
select all intended material cells, including overlap cells. A single frame maps
that arrangement's local coordinates into world space. One finite positive
distance and one reverse flag apply to the entire operation. The end cap lies at
`frame.origin + frame.normal * (reverse ? -distance : distance)`. Start and end
roles are relative to the authored plane, independent of direction.

## Material and topology

The service calls `RegionResult.union` before constructing any solid. Overlap
cells and shared boundaries unite; cancelled interior boundaries produce no
walls. Each separate union component produces one `Solid` with one closed shell.
Holes remain in both cap faces and receive inward-facing walls. Islands inside
holes remain separate bodies. Gaps, even below model tolerance, are preserved;
there is no snapping, healing, extension, or fusion with existing scene solids.

Caps use analytic planes, straight portions use planar walls, and circular
portions use analytic `CylinderSurface` walls with `CircularCadCurve` edges and
explicit trims. Arcs keep their center, radius, start and signed sweep. Existing
region-engine circle seams remain analytic patches; no sampled polygon or mesh
is stored in the model. Rendering may tessellate this geometry later.

Each loop creates one vertex per boundary junction at each end, shared by its
caps, adjacent walls, and axial edges. Circular boundary uses share curve
instances and trims with their cap counterparts. Wire traversal and face
orientation together give opposite effective edge use across adjoining faces.
Reverse extrusion changes cap orientation and wall traversal while retaining
outward material normals, including inward radial normals around holes.
`Solid`/`Shell.isClosed` validate the resulting manifold topology.

## Diagnostics and atomicity

Always check `result.isValid`. Rejection returns no volumes or solids, even if a
previous component was successfully built. Diagnostics contain a code, message,
error severity, selected region IDs where applicable, and upstream source IDs.

| Code | Meaning |
| --- | --- |
| `invalidDistance` | Zero, negative, NaN, or infinite distance. |
| `emptySelection` | No validated bounded cells were selected, including open-only input. |
| `unknownRegion` | At least one ID is unavailable in the supplied arrangement. |
| `invalidProfile` | The planar engine reported an invalid arrangement; its original errors are also retained. |
| `nonManifoldSelection` | Upstream union rejected point-connected components or a hole touching its outer boundary. |
| `unrepresentableGeometry` | Finite arithmetic cannot represent positive volume, distinct world vertices, valid analytic edge endpoints, or unambiguous component lineage. |

Other planar-engine diagnostic codes and source IDs pass through unchanged,
including warnings. Open or dangling inputs excluded by the engine do not
invalidate unrelated selected bounded cells. The service accepts an immutable,
validated frame; invalid frame construction already throws `ArgumentError`.

World-space placement can collapse geometry at extreme coordinate scales or
exceed finite range. Such an operation is rejected instead of publishing a
partial solid. The service uses the existing frame distance policy for analytic
edge endpoint agreement, never to merge distinct profile junctions. Component
lineage uses interior queries in local coordinates; inability to resolve those
queries conservatively rejects the operation. This is a double-precision engine,
not an arbitrary-precision general solid Boolean kernel.

## Provenance and future output references

Each `ExtrudedVolume` retains its union profile. Its face outputs hold the exact
face instances used in the solid, a start-cap/end-cap/wall role, deterministic
operation-local keys, and `RegionReference`s to the original selected cells in
that component. Each cap carries all outer and hole portions; each wall carries
its one originating analytic portion. Every portion retains **all** source IDs
and directed parameter intervals, including duplicates and split portions.
Intervals describe original profile traversal, even when a generated wire or
face orientation is reversed. Cancelled internal boundaries have no wall output.

A future feature adapter can expose these face/body keys and resolve region and
boundary lineage explicitly. Keys such as `volume:union:0:wall:0:1` are snapshot
identities, not persistent topological names. Rebuilds that reorder components or
split/remove boundaries need lineage resolution and explicit missing/ambiguous
handling; face indices and proximity must not become silent fallback names.
There is no sketch-dependent history feature in this implementation.

Result collections and provenance are immutable. Legacy `Vertex.vector` remains
mutable: consumers own the returned solids, and outputs deliberately reference
those same vertices rather than defensive copies. Independent extrusion calls
construct independent topology and never mutate the planar input arrangement.

## Verification

Explicit fixtures cover rectangle, disk, annulus, mixed line/arc semicircle,
overlapping and shared-boundary rectangles, overlapping circles, separated
profiles, multiple holes, and nested islands. The core fixtures run in XY,
translated XZ, and translated oblique frames in both directions. Tests check
closure, opposite edge use, shared vertex/curve identity, analytic surface
membership, cap placement, outward normals, hole exclusion, and provenance.

`test/support/extrusion_validation.dart` independently integrates the generated
B-rep with the divergence theorem, using planar flux and exact cylindrical flux.
It does not read region area or the service distance. Those volumes are compared
with fixture formulas: width × height × distance, πr² × distance,
π(R² − r²) × distance, semicircle area, rectangle inclusion/exclusion, and the
analytic circular lens formula. Failure tests cover invalid distances and
profiles, point/tangent contacts, sub-tolerance gaps, world-space collapse,
underflow/overflow, and atomic rejection after an earlier component was built.

Run `flutter test` and `flutter analyze` from the worktree root.
