# Headless sketch constraints

Task 10's sketch model is the prerequisite. `SketchDefinition` now owns immutable
`SketchConstraint` values keyed by caller-assigned `SketchConstraintId`s. Entity
and point references use existing stable `SketchEntityId`s; coordinates, collection
indices, and nearest geometry never identify a reference. Removing a referenced
entity requires updating its constraints in the same edit. `copyWith` reserves
removed constraint IDs in `retiredConstraintIds` and prevents retained IDs from
changing relation kind. Undo restores earlier identities. Version 2 parameters
encode all constraints, dimensions, fixed coordinates, and retired identities;
version 1 unconstrained definitions still decode. No external registry is needed.

## Relations and units

`SketchConstraint(kind: ..., references: ..., values: ...)` validates arity and
finite values. `SketchDefinition` validates reference existence and entity kind.
Ordered roles are explicit:

| Kind | References | Values in local model units |
| --- | --- | --- |
| `coincident` | point, point | none |
| `pointOnLine` | point, segment | none |
| `pointOnCircle` | point, circle | none |
| `horizontal`, `vertical` | segment | none |
| `parallel`, `perpendicular` | segment, segment | none |
| `lineLength` | segment | positive length |
| `distance` | point, point | nonnegative distance |
| `radius`, `diameter` | circle | positive dimension |
| `equalLengths` | segment, segment | none |
| `equalRadii` | circle, circle | none |
| `fixedPoint` | point | x, y |
| `fixedPrimitive` | segment | start x, start y, end x, end y |
| `fixedPrimitive` | circle | center x, center y, positive radius |

**Point-on-line means the supporting infinite line**, including positions beyond
both endpoints. It does not constrain a point to the bounded segment. Horizontal
and vertical use local support axes. Direction relations ignore endpoint order;
parallel includes antiparallel, and perpendicular accepts either handedness.
`SketchConstraint.fixPrimitive` captures explicit authored positions/radius, so
later authored edits cannot move the fixed target silently. Fixing a primitive
also restricts shared endpoint or center points through their references.

```dart
final constrained = authored.copyWith(constraints: [
  SketchConstraint(
    id: SketchConstraintId('base-horizontal'),
    kind: SketchConstraintKind.horizontal,
    references: [SketchEntityId('base-line')],
  ),
  SketchConstraint(
    id: SketchConstraintId('base-length'),
    kind: SketchConstraintKind.lineLength,
    references: [SketchEntityId('base-line')],
    values: [20],
  ),
]);
final result = const SketchSolver().solve(constrained);
if (result.isValid) {
  final inputs = const SketchPlanarAdapter().adaptSolved(result.geometry!);
  // Explicitly feed inputs into the region engine and downstream operations.
}
```

## Authored and solved state

Solving never modifies `SketchDefinition`. A valid `SketchSolveResult.geometry`
is an immutable `SolvedSketch` with separate point coordinates, circle radii,
unchanged primitive IDs/references, and point representatives. `SketchGeometry`
contains `definition` (authored), `solution` (classification/diagnostics), `solved`
(derived coordinates), and the resolved support frame. Downstream features should
use `adaptSolved(data.solved)`. Compatibility `adapt(definition)` explicitly
solves the definition first and throws for failed solving; it never publishes
unsolved constrained coordinates.

Shared point IDs and transitive explicit coincidence constraints use one pair of
solver variables and exactly equal published coordinates. A zero point distance
also unifies its points. Canonical representatives and all numerical ordering use
sorted stable IDs. The adapter performs no proximity snapping; a representable
unconstrained gap stays open even if smaller than solver or region tolerances.
The planar region engine independently recognizes proven geometric intersections
and exact incidence; it does not bridge gaps. Solved geometry creates no CAD
vertices, wires, faces, region selection, or inferred constraints.

## Numerical policy and result classification

The solver translates/scales local coordinates by a deterministic characteristic
length, then uses damped least squares with analytic forward differentiation.
Each trial must decrease residual cost and preserve positive circle radii.
Defaults are explicit in `SketchSolverSettings`:

- Absolute distance tolerance: `1e-8` in model units.
- Angular tolerance: `1e-10`, dimensionless unit-direction cross/dot residual.
- Rank tolerance: `1e-9` for row-normalized Jacobian rank.
- At most 120 iterations and 20 damping trials per iteration.
- At most 512 reduced variables and 2048 scalar equations.

Lengths, equal lengths, incidence distances, and fixed coordinates use length
residuals. Radius is compared to half a diameter so the diameter equation also
uses radius-length units. Direction equations normalize each direction before
cross/dot products, rather than comparing length-squared values with a length
threshold. Every equation must satisfy its own tolerance; aggregate cost alone
cannot establish convergence. Published model coordinates are checked again
after undoing normalization. Nonfinite or unrepresentable calculations fail.

Freedom comes from pivoted, reorthogonalized Jacobian rank after structural
coincidence elimination, never equation counting. It includes translations and
rotations: a noncollinear triangle constrained only by three independent side
lengths retains three freedoms. Rank measures local differential freedom at a
regular solution, not global uniqueness or the number of disconnected solution
branches. Mirror solutions are selected deterministically from authored seeds.

| Status | Meaning and output policy |
| --- | --- |
| `underconstrained` | All relations satisfied, positive freedom; valid downstream geometry. |
| `fullyConstrained` | All relations satisfied, zero local freedom; valid downstream geometry. |
| `redundant` | Satisfied dependent equations, with deterministic constraint IDs; valid geometry and separate freedom count. |
| `conflicting` | Incompatible dimensions/triangle inequality, or an unsatisfied regular stationary system with inconsistent augmented Jacobian rank. |
| `numericalFailure` | Limits, undefined directions, range problems, nonstationary stalls, or unresolved singular freedom. |

Redundancy takes status precedence over under/full classification, but does not
hide `degreesOfFreedom`. A constraint can be partly redundant. Sorted-ID order
determines which dependent constraint is reported. Coincidence cycles are
redundant without sacrificing exact connectivity. Zero distance restricts both
coordinates, rather than being treated as one scalar freedom restriction.

At a singular stall, up to three deterministic perturbations attempt to recover
within the iteration limit. Metric/linear systems with rank loss at an otherwise
satisfied solution report `singularSolution`, avoiding claims of finite freedom
from second-order rigidity (for example a degenerate triangle). Direction systems
can have dependencies that hold only on their solution manifold; their rank
remains a local differential measure. Nonlinear conflict diagnosis is local and
is not a proof of global infeasibility for every possible branch. Ambiguous
singular stalls report numerical failure rather than asserting conflict. Required
zero-length line directions fail explicitly. Unconstrained zero-length segments
remain allowed for the planar region engine to diagnose.

`SketchFeature.evaluate` solves before publishing. A failed solve raises a
structured `FeatureEvaluationFailure` with issue `constraintSolveFailed`.
`FeatureResult.diagnostics['sketchSolve']` contains status, iteration count, and
constraint IDs, residuals, and tolerances. Current outputs are empty, descendants
are blocked, and previous successful geometry is retained only in
`diagnosticOutputs`. References and valid data/geometry enumeration never use
those inspection outputs. Constraint/geometry edits and undo/redo reevaluate and
recover through normal document history.

## Interactive drag API

`SketchDragTarget(pointId: ..., x: ..., y: ...)` is temporary input to
`SketchSolver.solve(..., dragTargets: [...])`. The solver first tries targets as
temporary fixed positions. On success it analyzes only persistent constraints;
targets do not change persistent freedom or redundancy. For unreachable targets,
it solves persistent relations from target-seeded coordinates. This is a local
projection, not a guaranteed globally closest solution. If a seed collapses a
required direction, the original feasible geometry may be retained. Each phase
has the same explicit work limits; a drag uses at most three solve phases.

`SketchFeature.drag(controller, featureId, targets)` stores accepted solved
coordinates as the next authored seed through `updateParameters`, preserving
constraint targets and IDs. A failed drag returns diagnostics without editing.
Use normal controller transactions to group previews:

```dart
controller.beginTransaction('Drag sketch');
SketchFeature.drag(controller, sketchId, [
  SketchDragTarget(pointId: SketchEntityId('corner'), x: 25, y: 8),
]);
// Additional previews can use the same transaction.
controller.commitTransaction(); // One undo entry; or cancelTransaction().
```

No constraint UI, screen-space snapping, inferred constraints, or sketch editor
is introduced. Verification includes independently known solutions, mixed
relations, rigid motion, redundancy/conflicts, singular recovery, numerical
budgets, dimensional tolerances, exact connectivity and small open gaps,
determinism under collection permutations, fresh-document reconstruction,
downstream failure/recovery, and drag transactions.
