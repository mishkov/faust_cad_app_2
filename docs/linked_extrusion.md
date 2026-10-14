# Document-linked extrusion

Tasks 10–13 supply solved sketch data, constraints, persistent profile lineage,
and the sketch workspace. `ExtrudeFeature` consumes that sketch output through
an `OutputReference`, making sketch geometry, constraints, and resolved support
ordinary document dependencies. Its value parameters store a
`ProfileSelectionReference`, finite positive `distance`, and `reverse`.
Source identity is the sketch feature ID plus its `sketch` output key.

Evaluation adapts the current solved sketch through `SketchPlanarAdapter`, builds
cells with `PlanarRegionEngine`, resolves every stored profile atomically, and
calls `AnalyticExtrusionService`. The engines own all intersection, union, hole,
and analytic solid construction algorithms. Selected overlapping or edge-adjacent
cells unite; disconnected components become separate new bodies. Selecting only
an annular cell preserves its hole; selecting its inner disk too fills that hole.
Point-only material contact is rejected. Existing scene bodies remain independent.

`ExtrusionLineageAdapter` publishes body, cap, and identifiable wall outputs.
Later sketches attach through normal named-face support resolution. Distance and
reverse preserve authored cap roles; geometry and support edits automatically
rebuild descendants. Task 12's conservative boundary correspondence applies:
changed topology can break a profile/cap reference, and ambiguous curved wall
patches are withheld from attachment. No index or nearest-face fallback is used.

## Interactive workflow

Create a sketch and choose **Extrude regions** in its workspace, carrying its
current region multiselection into the extrusion editor. Alternatively choose
**Extrude [sketch]** in the CAD panel. Click filled profiles to toggle them, or
use the region checkboxes. Profiles fit the canvas initially; scroll/pinch zooms
and dragging pans. Enter a distance and toggle **Reverse**. The neighboring solid
view previews the evaluated document; drag to rotate and scroll to zoom.

**Confirm extrusion** accepts only a valid current evaluation and records one
undoable operation. **Cancel** or Escape restores all starting definitions and
outputs and preserves redo. **Edit [extrusion]** reopens its stored selection,
distance, and reverse option. Transactions hold evaluated draft definitions;
preview changes never append committed history entries. Invalid distance,
selection, sketch solve, support, and profile references show diagnostics and
withhold current generated bodies. Broken selections can be cleared and reselected.

After confirming, pick a named planar cap or wall and choose **Sketch on selected
face**. Its support follows upstream distance, reverse, sketch, and support edits.
The CAD panel also shows failed/blocked feature messages after leaving the editor.

## Verification

`flutter test` covers all analytic fixtures through the production feature and
through widget controls, with independent B-rep volume integration, holes,
multiselection, point-contact rejection, constraint solves, upstream face support,
cap picking, a second attached sketch, distance/reverse edits, cancellation,
reopening, undo/redo, and stale-result suppression. Interactive annulus previews
are available in `lib/extrusion_editor/extrusion_preview.dart` at desktop and
compact sizes. Run `flutter analyze` for static checks.

The renderer also verifies the reported circle/polyline partial extrusion over
40 camera orientations, including bottom and nearly edge-on views. Pixel tests
check that the sketch rim stays on its projected cap boundary after rotation and
viewport resizing. Visibility uses bounded contour half-plane clipping and
viewport-complement canvas masks, avoiding native path Boolean failures on
repeatedly cut near-coincident boundaries. Canvas save/restore pairs use
`try/finally`; occlusion holes and disconnected concave portions remain intact.
