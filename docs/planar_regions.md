# Analytic planar regions

The headless entry point is `lib/planar_regions/planar_regions.dart`. Task 1's
`PlanarFrame` and `GeometryTolerance` and Task 2's analytic circular-curve/trim
foundation are already on main (`dfbf5cc`, `eaba9ff`). Callers can use a planar
frame to obtain local coordinates. This engine accepts independently identified
`PlanarSegment` and `PlanarCircle` values, without importing Flutter, editor
entities, `Wire`, `Face`, or solid topology. No sketch UI or extrusion is added.

```dart
final engine = PlanarRegionEngine();
final arrangement = engine.build([
  PlanarCircle(id: 'outer', center: Vector2.zero(), radius: 3),
  PlanarCircle(id: 'inner', center: Vector2.zero(), radius: 1),
]);
final annulus = arrangement.regions.singleWhere((r) => r.holes.isNotEmpty);
final material = arrangement.union([annulus.id]); // Keeps the inner hole.
final filled = arrangement.union(arrangement.regions.map((r) => r.id));
// filled contains one radius-3 disk with no hole.
final location = annulus.locate(Vector2(2, 0), boundaryDistance: 1e-10);
final reference = arrangement.reference(annulus.id);
final resolution = engine.build(changedInputs).resolve(reference);
```

Input IDs must be nonempty and unique. Preserve them when editing the same
semantic geometry; never reuse one for unrelated geometry. Segment parameters
run from 0 at start to 1 at end. Circle parameters are counterclockwise radians
from local +X. Inputs copy vectors and all result collections are immutable;
vector getters return copies. Invalid input values or unsupported input types
throw `ArgumentError`. Zero-length segments are valid input with a diagnostic.

## Arrangement and selectable cells

The engine sorts inputs by ID, computes line/line, line/circle, and circle/circle
intersections, and splits analytic boundaries at intersection parameters. Circles
also have deterministic 0 and π seams, so no special self-loop representation is
needed. Geometrically duplicated portions become one graph edge with **all**
source IDs and directed parameter intervals retained. `BoundaryPortion` preserves
lines or analytic center/radius/start/sweep arcs; no polygon approximation is used
for intersections, topology, areas, containment, or unions. Adjacent arc endpoints
can differ by floating-point evaluation roundoff while sharing a constructed
intersection vertex; they are not inferred to connect by proximity.

Bridge edges are removed from face walking and reported as open boundaries.
The remaining directed half-edges are ordered by outgoing tangent and signed
curvature. Curvature orders exact tangent contacts. Face orbits are decomposed at
repeated vertices into simple loops. Positive loops bound material cells;
negative loops are assigned to the smallest enclosing positive loop with no
shared edge. The unbounded exterior is excluded. Outers are counterclockwise and
holes clockwise. Analytic signed areas use the boundary integral with translation
removed to reduce cancellation.

Cells are atomic: two intersecting circles yield two crescents and their lens.
Two concentric circles yield a disk and an annulus, not two overlapping disks.
Three nested circles yield a disk and two successive annuli. Regions can have
multiple holes. An interior dangling line does not partition a bounded cell;
a diameter or a boundary-to-boundary chord does.

`locate` reports `inside`, `outside`, or `boundary` and excludes hole interiors.
Containment counts analytic ray crossings, splitting angular **query intervals**
at extrema without changing model arcs. `boundaryDistance` defaults to zero;
callers can pass a model-space distance for proximity classification. Proximity
can classify both sides of a very narrow feature as boundary; it never changes
connectivity or selects a neighboring cell automatically.

## Union and non-manifold selection

`RegionResult.union` takes current arrangement-local region IDs. Duplicate IDs
are idempotent; unknown IDs throw. Oppositely directed shared boundaries cancel.
The surviving analytic boundaries are re-walked and nested into material
components. Overlapping profiles become one material component when all relevant
atomic cells are selected; adjacent selected cells sharing an edge also unite.
Separated components stay separate, even across a gap below model tolerance.
A hole remains until its interior cells are also selected. Empty selection is a
valid empty material result for a valid arrangement.

A surviving boundary vertex must have exactly two incident portions. A point-only
contact between selected components, or a hole touching its outer boundary,
returns `nonManifoldSelection` with **no material**. For externally tangent disks,
either disk alone is valid but their combined selection is rejected. For an
internally tangent pair, the touching annulus alone is rejected; selecting its
disk too cancels the hole and yields a valid filled outer disk. Callers must check
`RegionSelection.isValid` before treating a selection as extrudable material.

## Numerical policy and diagnostics

Exact dyadic predicates using the binary values of original finite doubles guard
line incidence and circle contact classifications. They do not round a positive
gap into a contact. Intersection coordinates and parameters still use double
arithmetic in translated, uniformly normalized coordinates. The engine never
snaps endpoints with `GeometryTolerance.distance`, never extends a segment, and
never repairs an open chain. Distance tolerance only identifies tiny inputs for
warnings; tiny representable closed geometry is retained.

Construction ordering uses a fixed floating-point roundoff budget (64 machine
epsilons in normalized parameter/direction calculations), separate from the
model-space distance policy. If exact predicates and numerical construction
disagree, events cannot be ordered safely, normalization loses distinct original
coordinates, or a material area cannot be represented, the result is invalid and
publishes no cells. Such a case requires revised input precision/scale, rather
than a guessed connection. Extremely small areas can underflow and very large
areas can overflow even when individual input coordinates are finite. Exact
predicates protect incidence decisions, not arbitrary-precision intersection
coordinates or a general CAD-kernel robustness guarantee.

| Code | Outcome |
| --- | --- |
| `zeroLength` | Warning; segment contributes no boundary. |
| `tinyGeometry` | Warning; input is retained without snapping or polygonization. |
| `coincidentCircle` | Warning; exactly equal centers/radii share one analytic boundary with all IDs. |
| `overlappingSegment` | Warning; collinear overlap/contact is split and overlapping portions deduplicated. |
| `tangency` | Warning; a tangent vertex is retained, with no artificial crossing or overlap area. |
| `openBoundary` | Warning; open/dangling/bridge portions form no material; independent bounded cells remain selectable. |
| `numericAmbiguity` | Error; unsafe event ordering or intersection construction publishes no cells. |
| `numericRange` | Error; unrepresentable coordinates, normalized features, or material areas publish no cells. |
| `nonManifoldSelection` | Selection error; point-connected boundaries publish no selected material. |

An open rectangle, including one with a tiny positive endpoint gap, remains open
and produces no region. Open inputs can coexist with valid circles or rectangles;
the diagnostic lists excluded source IDs. Near-coincident but distinct circles
are not deduplicated. A near-tangent overlap below construction resolution is
rejected explicitly; an exactly provable separation stays separated.

## Provenance and references

Every returned directed portion carries all original source intervals. Reversing
a portion reverses its interval. Circle intervals are unwrapped, so 2π can be an
endpoint; a clockwise hole has descending intervals. Shared-boundary cancellation
removes interior portions from a union's external boundary but does not mutate
the original cells or their provenance.

`region:N` and `union:N` are deterministic **local** IDs, never persistent names.
Input permutation alone preserves region ordering, diagnostics, provenance, and
selection results. Within the original immutable result a `RegionReference`
resolves its exact cell. After a rebuild it matches the sorted set of outer source
IDs and the sorted collection of hole source-ID sets. Coordinates, proximity,
face indices, and parameter values are intentionally excluded from that semantic
match, so an unambiguous rectangle reference survives a size or position edit.

A unique matching current cell is `resolved`, no match is `missing`, multiple
matches are `ambiguous` with every candidate, and a numerically invalid arrangement
is `unavailable`. This rule is deliberately conservative: different cells bounded
by the same two circles are ambiguous after a rebuild, even when unchanged
geometry would permit proximity guessing. Added splitting boundaries, deleted
sources, or changed hole lineage can retire a reference as missing. This is not a
general topological naming solution. Future sketch-profile features must handle
all statuses explicitly and can add their own authored semantic constraints.

## Verification and limits

Tests cover rectangles, circles, overlapping circles/rectangles, partial and full
shared segments, diameters, multiway crossings, self-crossing chains, nested disks
and annuli, multiple holes, duplicate/reversed/overlapping segments, coincident
circles, internal/external/line tangencies, tiny geometry, translated coordinates,
intentional gaps, dangling bridges, order independence, mutation isolation, and
all reference statuses. Seeded multi-circle arrangements additionally compare
cell and union membership with independent circle-distance queries and check
area conservation.

The implementation uses pairwise intersection discovery, linear endpoint lookup,
and graph traversal with recursive bridge discovery. It is intended for modest
sketch profiles, not massive arrangements. There is no spatial index, general
spline/ellipse support, arbitrary independent-region Boolean API, persistence,
feature evaluator integration, sketch UI, or solid construction in this task.
