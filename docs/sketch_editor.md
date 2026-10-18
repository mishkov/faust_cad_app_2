# Sketch editor

This editor uses the completed tasks 10–12: `SketchDefinition`, `SketchSolver`,
`SketchFeature`, `SketchPlanarAdapter`, and semantic profile references. It adds
in-memory authoring and presentation; no extrusion command or disk persistence.

## Creating and reopening

Click the pencil **Sketch** button at the center of the scene's left edge.
Temporary XY, XZ, and YZ plane patches appear near the origin, with the top-center
hint “Hint: select plane to start sketch on it”. Click a plane patch or a visible
named planar face to start; face picking works regardless of the inspection
selection mode. Escape cancels plane selection without creating a document edit.
Clicking the Sketch button again keeps selection active. Unnamed, ambiguous,
curved, and occluded faces remain unattachable under the viewport selection API.
**Open sketch-N** reopens a retained sketch.

The camera animates to face the resolved plane, switches to orthographic
projection, and then enables the sketch tools in the left panel. Drawing stays
inside the CAD scene with the model visible, including for arbitrarily rotated
or reversed planar supports. Sketch pan and zoom also move the scene camera so
model geometry and local sketch coordinates remain aligned. Face trims and
holes remain visible in the model; they never clip the sketch. Permanent red X,
green Y, and blue Z axes extend from the origin in their positive directions.
The active plane canvas takes interaction priority and deliberately removes
solid occlusion so geometry beyond a support boundary remains editable. Leaving
with **Finish sketch** cancels unfinished interaction and restores the entire
previous CAD camera. Pan and zoom within sketch mode do not alter that saved
camera. The view resolves attachment placement again after producer changes.
A broken support removes interactive geometry and regions and identifies the
support to restore; undo can recover it.

## Interaction

- **Line:** click the first and second endpoints. Each line is one edit. Click
  another pair for another line; Esc discards the unfinished preview.
- **Circle:** click the center then a radius point. The circle/radius guide and
  a live model-unit measurement preview the operation.
- While drawing, enter a positive length or radius and press Enter. The geometry
  and a persistent dimension are committed together as one undo entry.
- **Select:** click points or curves; click inside a filled cell to select a
  region. Shift-click adds/removes entities or regions. Alt-click cycles
  overlapping entities; use Shift+Alt to select both independent corner points.
  The entity checklist is also available when screen hits overlap.
- Drag a point, line, or circle in Select mode. Lines target both endpoints;
  circles translate their center. Persistent constraints take precedence over
  the desired cursor position. Release commits the entire drag as one undo
  entry. Esc, pointer cancellation, tool changes, and leaving restore its
  starting definition; cancellation preserves redo.
- Delete removes selected entities and their dependent primitives/constraints.
  Removing a primitive also removes its unused endpoints/center; retained shared
  points and unrelated entities remain. Selecting a constraint marker or row
  makes Delete remove that constraint.
- Scroll or pinch to zoom about the cursor; middle/right drag or trackpad pan
  translates the plane canvas. Undo/redo buttons and Cmd/Ctrl+Z and
  Cmd/Ctrl+Shift+Z work in sketch mode and the CAD view.

Explicit states are idle, first/end line point, circle center/radius, and drag.
Drawing previews do not mutate the document. A drag uses a
`DocumentController` transaction for evaluated previews. All committed edits
pass through the controller and preserve authored entity and constraint IDs.
IDs are not inferred from coordinates; the model reserves retired identities.

## Snapping and constraints

**Snap placement** uses a 10-pixel endpoint/axis threshold. Picking uses an
8-pixel entity threshold. These are screen interaction distances and never
change solver or region-engine model tolerances. Teal guides explicitly say
**placement only**; they do not add constraints. Newly drawn points remain
independently identified even when placed at the same coordinates. Add
Coincident to keep independent endpoints joined through later edits. The
adapter and region engine never close a representable gap using a UI threshold.
Real analytic intersections still produce regions.

Selection exposes only applicable controls:

| Selection | Relations |
| --- | --- |
| One line | Horizontal, Vertical, Length, Fix primitive |
| One circle | Radius, Diameter, Fix primitive |
| One point | Fix point |
| Two points | Coincident, Distance |
| Point + line/circle | Point on line / Point on circle |
| Two lines | Parallel, Perpendicular, Equal lengths |
| Two circles | Equal radii |

Dimensions use finite model-unit values. Length/radius/diameter must be positive;
distance may be zero. The constraint list and purple canvas markers identify
persistent relations. Select a marker/row to inspect its references; click a
dimension marker or the row's edit icon to change its value. The row's remove
control and undo provide recovery. Freedom and solver classification stay
visible. Conflicts report affected constraint IDs/messages/residuals; invalid
solves withhold current geometry and all selectable cells. Redundant relations
are reported separately. Reopening a conflicting sketch retains its authored
constraints for correction.

## Presentation and selection

`sketch_editor/presentation` owns solved strokes, filled region paths, markers,
projection and hit testing. It never constructs CAD vertices, edges, wires, or
faces from sketch entities. Analytic local coordinates drive region picking;
line/arc sampling is presentation data only. Filled paths preserve holes.

Active hit priority is points, nearest curves, constraint markers, then regions.
Alt-click cycles the entity hits instead of guessing among coincident points.
Region selection captures `ProfileReference` with a sketch feature/output scope,
and resolves it after every rebuild. Missing/ambiguous/unavailable profiles have
no highlighted substitute. Their reference remains available for undo recovery;
no arrangement index or nearest-region fallback is used. Entity selections are
pruned on deletion and cleared by editor undo/redo. Evaluation failures withdraw
cells instead of keeping a stale fill.

In the CAD view, valid inactive sketches are drawn through a separate
`SketchScenePainter` using the existing CAD camera. Foreground face triangles
are clipped against each sketch plane and suppress both fill and strokes.
Coplanar support faces do not suppress their sketch. This overlay ignores pointer
input, preserving CAD face/body picking; reopening happens through the sketch
list. In the active editor, the interactive sketch overlay remains visible over the
model so all sketch geometry can be edited. CAD topology and tessellation never supply sketch identity.

## Verification

`test/sketch_editor` covers authored drawing of rectangles/circles, numeric
creation and editing, every agreed constraint type, constrained point/primitive
translation, conflicts and recovery, deletion, cancelled drawing/drag, history
coalescing and redo preservation, pixel thresholds versus true gaps, overlap
cycling, region-reference retirement/undo recovery, all principal planes,
rotated/reversed/translated face attachment and broken-support recovery, plane
projection, holes, and foreground/coplanar occlusion. Widget tests exercise real
pointer and keyboard handlers, controls, dimension validation/cancellation,
reopening and camera restoration. Existing CAD camera/rendering/history tests
remain part of `flutter test`.
