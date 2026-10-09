# faust_cad_app_2

A Flutter CAD viewer with wireframe and shaded rendering.

## Render modes

`CadScene.renderMode` accepts `CadRenderMode.frame` (the default) or
`CadRenderMode.shaded`. The enum is exported by `cad_scene.dart`.

```dart
CadScene(
  cameraConfig: camera,
  cadObjects: objects,
  renderMode: CadRenderMode.shaded,
)
```

Frame mode draws all boundary edges, including hidden geometry. Shaded mode
fills supported planar and cylindrical faces with opaque gray, adds black visible boundary edges, and
uses ambient plus directional lighting fixed above and to the camera's right.
Faces render from either side. Trimming holes stay open, revealing geometry
behind them. Depth comparisons hide obscured faces and edges across all objects,
including standalone wires and grid lines, independently of object order.
Intersecting faces are clipped by their local perspective depth rather than
sorted as whole objects. Both modes clip geometry to the camera view frustum.

The renderer supports linear/circular boundaries, trimmed `PlaneSurface` faces
(including disks, annuli, concave loops, and holes), and nonperiodic
`CylinderSurface` patches bounded by coaxial circular arcs and axial lines,
including angular/axial windows. Boundary loops must be simple and lie on their
surface. Full-turn periodic faces and other curve/surface types are not supported.
Shading describes surface illumination; cast shadows are not rendered.

## Document and feature history

`CadDocument` owns immutable feature definitions and publishes complete evaluation
snapshots. Features have stable IDs, value parameters, explicit dependencies, and
named body/planar-face output references. Edits rebuild affected descendants in
deterministic dependency order. Failed features block descendants and retain prior
geometry only for diagnostics; independent valid bodies remain renderable.

```dart
final document = CadDocument(
  evaluators: {CubeFeature.type: CubeFeature.evaluate},
  features: [
    FeatureDefinition(
      id: FeatureId('base'),
      type: CubeFeature.type,
      parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 20},
    ),
  ],
);
CadScene(
  cameraConfig: camera,
  geometry: document.evaluation.geometry,
  geometryRevision: document.evaluation.revision,
);
```

The demo uses evaluated Cube bodies. See [the foundation contract](docs/feature_history.md)
for editing, failure states, reference resolution, copy isolation, and scope.

## CAD topology and geometry

- `Vertex` stores a position; `Edge` connects vertices using a `CadCurve`.
- `Wire` references an ordered, connected chain of edges and may be open or
  closed. Connectivity and closure use shared vertex instances.
- `CadSurface` describes untrimmed mathematical geometry. `PlaneSurface` defines
  an infinite plane using an origin and normal, independently of any boundary.
  Other surface types can extend `CadSurface` as curved geometry is added.
- `Face` references a surface, one closed `outerWire`, and an immutable list of
  closed `innerWires` representing holes. It does not duplicate wire geometry.
- `Shell` references an immutable, non-empty list of connected faces. Faces
  connect through shared boundary vertex instances, including hole boundaries;
  equal coordinates on distinct vertices do not establish connectivity.
  Connectivity can be transitive, so each face need not touch every other face.
- `Solid` references an immutable, non-empty list of closed shells. The first
  shell defines the outer material boundary; further shells represent cavities.
  Construction rejects open or non-manifold boundaries and duplicate shells.

For example, given rectangular wires on the XY plane:

```dart
final surface = PlaneSurface(
  origin: Vector3.zero(),
  normal: Vector3(0, 0, 1),
);
final face = Face(
  surface: surface,
  outerWire: rectangle,
  innerWires: [hole], // Omit for a face without holes.
);
final shell = Shell(faces: [face]); // A single face is an open shell.
```

The topology hierarchy is `Solid → Shell → Face → Wire → Edge → Vertex`. Solids
and shells preserve the supplied topology references without duplicating their
geometry. A cube's six connected faces form a closed shell; removing one face
creates an open shell. Both shells are supported, but only the closed shell can
bound a solid:

```dart
final solid = Solid(shells: [closedCubeShell]);
final solidWithCavity = Solid(shells: [outerShell, innerShell]);
```

Shell construction validates connectivity. `Shell.isClosed` checks that every
outer and inner boundary edge is paired with exactly one edge on a distinct
face, using shared endpoint instances, matching curves, and opposite traversal.
Linear edges with the same shared endpoints match regardless of curve instance;
other curves must share their curve instance. Circular edges must additionally
reference the same directed trim up to reversal; complementary arcs between the
same endpoints remain different boundaries. Pairing uses effective traversal,
including each face's orientation. Each face must visit a boundary
vertex only once, and faces around each vertex must form one connected fan, so
skins touching at only a vertex are rejected. Solid construction requires this
closed manifold topology. Geometric volume enclosure,
non-zero volume, self-intersection, cavity containment, and outward/inward
surface orientation remain the caller's responsibility.

`CadObject.build()` can return solids, shells, faces, wires, or edges. Frame mode
draws the supported edges of every shell boundary, including cavities and face holes;
shaded mode fills the supported surfaces and draws only visible edges. Face
construction validates topological closure; callers must ensure boundaries lie on the surface,
do not self-intersect, and contain their holes.

## Planar coordinates and numerical tolerance

`PlanarFrame` in `lib/cad_scene/geometry/planar_frame.dart` provides an origin,
unit local X/Y axes, and their right-handed normal (X × Y). It reuses
`PlaneSurface`; neither type stores sketch entities or boundaries. Vector inputs
are copied and vector getters/results cannot mutate the stored geometry.

The named frames have deterministic orientation and optional translated origins:

| Factory | Local X | Local Y | Normal |
| --- | --- | --- | --- |
| `PlanarFrame.xy` | +X | +Y | +Z |
| `PlanarFrame.xz` | +X | +Z | −Y |
| `PlanarFrame.yz` | +Y | +Z | +X |

The unnamed constructor validates unit, perpendicular axes. `fromPlane` preserves
the supplied plane's oriented normal and projects a preferred direction onto the
plane to choose local X. It rejects zero, nonfinite, or nearly normal preferred
directions instead of choosing an arbitrary fallback. Normal and direction
normalization supports very large and very small finite magnitudes.

```dart
final tolerance = GeometryTolerance(distance: 1e-7, angular: 1e-10);
final frame = PlanarFrame.fromPlane(
  plane: PlaneSurface(origin: Vector3(0, 0, 5), normal: Vector3(0, 0, 2)),
  preferredDirection: Vector3(1, 0, 0),
  tolerance: tolerance,
);
final world = frame.localToWorld(Vector2(2, 3)); // (2, 3, 5).
final local = frame.worldToLocal(world); // (2, 3), after membership validation.
final projected = frame.projectToLocal(Vector3(2, 3, 9)); // (2, 3).
final onPlane = frame.projectPoint(Vector3(2, 3, 9)); // (2, 3, 5).
final distance = frame.signedDistance(Vector3(2, 3, 9)); // +4 model units.
final hit = frame.intersectRay(
  rayOrigin: Vector3(2, 3, 9),
  rayDirection: Vector3(0, 0, -2),
); // (2, 3, 5).
```

`worldToLocal` validates plane membership and throws for points outside the
inclusive distance threshold. Accepted normal residuals are discarded.
`projectToLocal` and `projectPoint` deliberately accept off-plane points; calling
a projection does not establish that the original point lies on the plane.
`containsPoint` only classifies membership and never modifies a point.
`PlaneSurface` also exposes `signedDistance`, `containsPoint`, and `projectPoint`.

Ray intersection returns a new world point or `null` for parallel/near-parallel
rays, coplanar rays with no unique hit, and intersections behind the origin.
A transverse ray starting exactly on the plane hits at its origin. Directions
are normalized, so their magnitude does not affect classification. Distance
tolerance never clamps a negative ray parameter or moves its origin onto the
plane. Invalid inputs throw `ArgumentError`; calculations exceeding finite
floating-point range throw `StateError` rather than returning NaN or infinity.

`GeometryTolerance` separates two configurable numerical thresholds:

- `distance`: an absolute length in the model's own units, default `1e-8`.
  It must be finite and nonnegative; zero requests exact floating-point plane
  membership. Choose it for the model's scale and precision. No millimeter,
  meter, relative tolerance, or camera scale is assumed.
- `angular`: a dimensionless threshold in `(0, 1)`, default `1e-10`, used for
  unit-vector dot/cross products and axis unit-length error. It bounds the sine
  of angles near parallel and the absolute cosine near perpendicular. It is
  not an angle in radians or a model-space length.

These tolerances classify numerical agreement. They do not snap points, merge
vertices, close gaps, or bridge separated geometry. Existing topology continues
to require shared vertex instances. Future screen-space snapping must have a
separate policy measured in pixels; camera and rendering behavior are unchanged.

## Analytic circular boundaries

Task 1's `PlanarFrame` and `GeometryTolerance` provide the circle's planar basis
and numerical policy. `CircularCadCurve(frame: frame, radius: r)` is untrimmed
geometry with a finite positive radius and center at `frame.origin`. It owns no
vertices or topological boundary. Vector results are defensive copies.

The curve parameter θ is a finite angle in radians:

```text
C(θ) = center + radius * (cos(θ) * frame.xAxis + sin(θ) * frame.yAxis)
C′(θ) = radius * (-sin(θ) * frame.xAxis + cos(θ) * frame.yAxis)
```

Zero lies on +X; positive angles turn toward +Y, counterclockwise viewed from
+normal toward the plane. `circle.evaluate(θ)` is periodic; `circle.tangent(θ)`
is the derivative per radian, not a unit tangent.

An `Edge` on a circle requires `CircularTrim(startAngle: θ0, sweepAngle: Δθ)`.
The start is canonicalized into `[0, 2π)` and the signed sweep must satisfy
`0 < |Δθ| < 2π`. Positive sweeps are counterclockwise; negative sweeps are
clockwise. No shortest-arc inference occurs: sweeps `π/2` and `-3π/2` from the
same start describe complementary arcs with the same endpoint coordinates.

```dart
final circle = CircularCadCurve(frame: PlanarFrame.xy(), radius: 5);
final begin = Vertex(circle.evaluate(0));
final end = Vertex(circle.evaluate(math.pi / 2));
final quarter = Edge(
  begin, end,
  curve: circle,
  trim: CircularTrim(startAngle: 0, sweepAngle: math.pi / 2),
);
final oppositeUse = quarter.reversed(); // Same curve and shared vertices.
final profile = Wire.circular(circle); // Four exact arcs, not polygon chords.
final clockwiseProfile = profile.reversed();
```

`Edge.evaluate(t)` uses normalized traversal `t ∈ [0, 1]` and circle angle
`θ0 + Δθ*t`. `Edge.tangent(t)` is `C′(θ0 + Δθ*t) * Δθ`, the derivative per
normalized traversal parameter. Reversal swaps the shared endpoint instances,
starts at the old end angle, and negates the sweep. For linear edges these
methods evaluate endpoint interpolation and its derivative. Unknown curve types
throw `UnsupportedError` for evaluation and tangents.

Circular edge construction checks both vertices against their trimmed analytic
endpoints using `frame.tolerance.distance`, without moving or merging vertices.
Missing trims, nonfinite angles, zero/full-turn/multiple-turn sweeps, mismatched
endpoints, and collapsed circular edges are rejected. Shell validation rechecks
circular endpoints because vertex coordinates are mutable. Matching circular
boundaries requires shared endpoint and curve instances and agreement of start
and signed sweep up to reversal. The frame's angular threshold is used as a
radian roundoff threshold for this trim comparison; periodic start angles match.

`Wire.circular` creates at least two analytic arcs (four by default), with one
shared vertex at each junction and topological closure at the final junction.
`arcCount`, `startAngle`, and `clockwise` select the subdivision and traversal.
Two semicircles remain separate boundaries even though they share both vertices
and the same circle. A full-circle single edge and periodic face seams are not
supported. Existing collapsed linear-edge and manifold protections remain.

`Face.orientation` defaults to `FaceOrientation.forward`;
`FaceOrientation.reversed` negates the material normal and reverses effective
boundary traversal. `face.orientedNormal(surfaceNormal)` applies that sign and
returns a copy; `face.reversed()` retains the surface and all wires while
flipping orientation. Thus outward and cavity faces can share a parameterized
surface without changing its frame. Shell pairing uses this orientation as well
as edge traversal. Whether the chosen normal points outward from material is
still the caller's geometric responsibility. The current two-sided renderer
retains its existing behavior; circular tessellation, sketches, and extrusion
remain separate tasks.

## Cylindrical surfaces and reference solids

Tasks 1 and 2 supply the immutable planar frame, tolerance policy, circular arcs,
and face orientation used here. `CylinderSurface(frame: frame, radius: r)` is
untrimmed geometry with a finite positive radius. Its axis is `frame.normal`;
`frame.origin` defines axial zero and `frame.xAxis` defines angular zero.
Positive angles turn from local X toward local Y. The parameters are radians
and signed model-space axial length:

```text
S(θ, z) = frame.origin + r * (cos(θ) * frame.xAxis + sin(θ) * frame.yAxis)
          + z * frame.normal
N(θ) = cos(θ) * frame.xAxis + sin(θ) * frame.yAxis
```

`surface.evaluate(angle, axial)` accepts any finite angle and axial value;
`surface.normal(angle)` returns a fresh outward radial unit normal. Neither
method trims the surface. Normals follow the angular derivative crossed with
the axial derivative. `Face.orientation` reverses this normal for inner walls.
Vector results cannot mutate the frame. Invalid dimensions/parameters throw
`ArgumentError`; evaluation exceeding finite range throws `StateError`.

`Cylinder` and `Tube` in `lib/cad_scene/cad_objects/` are independently testable
fixtures/reference primitives. Their required `frame` places the base center at
its origin; finite positive `height` extends along its normal. Arbitrary axes
and angular reference directions use the existing frame constructor:

```dart
final frame = PlanarFrame.fromPlane(
  plane: PlaneSurface(origin: Vector3(3, 4, 5), normal: Vector3(1, 2, 3)),
  preferredDirection: Vector3(1, 0, 0),
);
final cylinder = Cylinder(frame: frame, radius: 3, height: 8).build().single;
final tube = Tube(
  frame: frame, outerRadius: 3, innerRadius: 1, height: 8,
).build().single;
```

Both return a fresh `Solid` with exactly one closed manifold `Shell`. A cylinder
has two disk caps and outward cylindrical walls. A tube requires
`0 < innerRadius < outerRadius`, has two annular caps, outward outer walls, and
inward inner walls. Its bore passes through both caps and belongs to the same
connected shell; it is not an enclosed cavity represented by a second shell.

`patchCount` defaults to four and must be at least two. Each wall patch has two
exact circular arcs and two axial linear boundaries; the caps reference those
same arc geometries and shared endpoint vertices. Adjacent patches share axial
boundaries with opposite effective traversal. The wall patches share one
untrimmed cylinder surface per radius. Splitting the circumference avoids a
full-turn edge or periodic seam topology; the subdivision is not tessellation.
Unresolvable axial boundaries at extreme placements are rejected during build.
Existing shell checks still reject missing/duplicate faces, incorrect traversal,
complementary arcs, independent coincident geometry, and mutated arc endpoints.

These objects do not create sketch features or execute extrusion commands.
The renderer tessellates these analytic fixtures without changing their topology;
the fixtures are not added to the viewer's default scene.


## Rendering tessellation and cache

`lib/cad_scene/rendering/tessellation/` contains derived samples and meshes;
`Edge`, `CircularCadCurve`, `CylinderSurface`, and `Face` remain analytic CAD
geometry. Both modes share these samples. Circular segments satisfy the sagitta
(chord deviation) bound in model units, with an additional angular bound for
smooth normals. Topological boundary matches, including reversed uses, reuse
exactly the same samples. Trimmed loops are triangulated with an even-odd slab
method in planar or unwrapped angular/axial coordinates. Splits interpolate the
existing boundary chords rather than resampling them, so neighboring faces
retain the same boundary geometry. Holes remain empty.

Cylindrical triangles carry analytic radial vertex normals with face orientation,
interpolated for smooth two-sided camera-fixed lighting. Triangle diagonals and
shared axial edges between patches on the same oriented cylinder surface are
never outlines. Open patches retain their axial borders; standalone wires retain
all their edges. Planar fills keep the existing single path and depth plane,
avoiding a visibility primitive for every coplanar triangle. Clipping happens in
camera space before projection. Shaded depth queries use a fixed screen grid and
stroke bounds to reduce unrelated face comparisons.

```dart
CadScene(
  cameraConfig: camera,
  cadObjects: objects,
  renderMode: CadRenderMode.shaded,
  tessellationSettings: TessellationSettings(
    chordError: 0.01,       // Model units, independent of zoom.
    maxAngle: math.pi / 12, // Radians; also controls lighting interpolation.
    maxSegmentsPerEdge: 512,
    maxTriangles: 20000,    // Total derived triangles per scene.
  ),
  geometryRevision: modelRevision,
)
```

`TessellationSettings` is exported by `cad_scene.dart`. The values above are the
defaults. Invalid quality values throw `ArgumentError`; exceeding a tessellation
budget throws `StateError` instead of allocating unbounded geometry or silently
relaxing the requested error. Camera zoom never triggers automatic refinement.
Callers should choose the model-space error for their model scale.

Each `CadScene` owns one `SceneTessellator` cache across camera and mode changes.
Quality changes or a changed `geometryRevision` invalidate the whole derived
scene. A coordinate/topology snapshot also detects in-place vertex edits and
fresh geometry returned by `CadObject.build()`. Manual painter users can supply
and reuse a `SceneTessellator`, or call `invalidateGeometry()` explicitly. The
cache retains only the latest scene; projection and visibility are view-dependent
and recalculated per paint. Model building and snapshot comparison run when a
painter is constructed; painting reuses its prepared render data. Supply updated
geometry (or construct a new painter for edited legacy objects) after model edits.

## Repeatable curved-rendering verification

Run accuracy, topology-preservation, cache, budget, pixel, and multi-camera tests:

```sh
flutter test test/cad_scene/rendering
flutter analyze
flutter test
```

Export deterministic images without editing the default scene:

```sh
CURVED_RENDER_OUTPUT=build/curved-rendering flutter test \
  test/cad_scene/rendering/curved_rendering_test.dart
```

The ignored output directory includes `gallery.png` (left to right: front, orbit,
rear, top, camera-inside; shaded above, frame below) and individual images:
front, orbit, rear, top, and camera-inside
clipping views in both modes, plus cylinder side views and end-on tube/bore/wire
checks. The fixtures include cylinders, a tube, a cube, and a wire for occlusion.
Pixel assertions check smooth lighting, opaque mesh interiors, absence of patch
seams, through holes, hidden circular wires, and visibility independent of object
order. No screenshots or fixture objects replace the viewer's default scene.

The headless [analytic planar region engine](docs/planar_regions.md) accepts
identified 2D segments and circles for future sketch profile selection, with
analytic boundaries, holes, provenance, and validated material unions.


## Viewport selection and associative planar supports

The viewer has Body / Planar face selection. Click a visible cube face to tint
its visible trimmed area and inspect its semantic reference, plane origin, local
X/Y axes, and normal. Selection and camera state do not edit document history.
No sketch drawing is implemented. The widget preview is in
`lib/screens/previews.dart`.

Reusable viewport input comes from `EvaluationSnapshot.materializeGeometry()`.
It copies valid evaluated bodies once, preserving explicit face correspondence.
Use the same materialized snapshot across camera-only builds, and replace it
when the document evaluation changes:

```dart
final evaluated = document.evaluation.materializeGeometry();
CadScene(
  cameraConfig: camera,
  evaluatedGeometry: evaluated,
  geometry: gridGeometry, // Additional geometry also participates in occlusion.
  geometryRevision: document.evaluation.revision,
  renderMode: CadRenderMode.shaded,
  selectionMode: ViewportSelectionMode.planarFace,
  selectedReference: selectedReference,
  onSelected: (hit) {
    selectedReference = hit?.faceReference;
  },
);
```

`ViewportPicker` is also usable without the widget. Its `ViewportHit` returns the
exact analytic face, owning body, world point, camera depth, and optional body
and face `OutputReference`s. Picking uses the renderer's bounded tessellation and
near plane. It honors rotated faces, finite trimming boundaries, holes, and
frontmost planar/cylindrical geometry regardless of selection mode. A curved
front face blocks planar picking behind it. Body mode selects solids. Planar
face mode rejects cylindrical walls. Face fills define picking in both render
modes; standalone wires/grid strokes are not selection targets. Curved trim rims
and cylindrical occlusion share the configured rendering chord approximation.
Only surfaces supported by the renderer participate.

A producing feature explicitly supplies `FeatureOutput.faceKeys` on its body
output: a map from semantic face-output key to the **exact Face instance in the
body**. `CubeFeature` supplies front/back/top/bottom/left/right. Also publish the
matching face output. `OutputKind.face` allows analytic faces whose surface type
may change; existing `OutputKind.planarFace` continues to enforce planarity.
There is no face-index or spatial matching fallback. Unnamed/ambiguous faces
remain geometrically pickable but have no attachable reference. The feature
adapter owns stable naming; extrusion's operation-local keys require an explicit
lineage policy before being used as persistent references.

Supports are immutable definition data on any `FeatureDefinition`:

```dart
final definition = FeatureDefinition(
  id: FeatureId('supported-feature'),
  type: 'my-feature',
  support: PlanarSupport.face(
    reference: selectedFaceReference,
    preferredDirection: Vector3(1, 0, 0),
  ),
);
// Or: PlanarSupport.principal(PrincipalPlane.xy), .xz, or .yz.
```

The producer automatically becomes a dependency. The document evaluator resolves
supports before invoking the consumer, exposes `context.support`, and retains
the resolved support on `FeatureResult.support` for inspection. Producer edits,
rebuilds, and undo/redo resolve the same feature/key/kind again. Self/mutual
support cycles use the existing cycle detection and never invoke evaluators.
Missing, ambiguous, unavailable, or nonplanar faces produce
`FeatureIssue.brokenAttachment` with a diagnostic and no valid consumer outputs.
A reference whose output kind changes is missing; it never silently changes kind.
Standalone `PlanarSupportResolution.resolve` provides the same resolution logic.

Face frames use Task 1's `PlanarFrame.fromPlane`: origin is the analytic plane's
origin; normal includes the face's material orientation; local X is the projection
of the stored, normalized preferred **model-space** direction. Local Y is normal
cross X. The direction is selected deliberately at attachment creation and never
switched during rebuild. It provides a deterministic world-axis convention,
rather than a rigidly transported edge axis. A nearly normal preferred direction
breaks the attachment instead of introducing a fallback or arbitrary flip.
Principal supports preserve Task 1's XY/XZ/YZ conventions.

`ResolvedPlanarSupport.frame` describes an infinite supporting plane.
`boundary` is a separate, defensively copied trimmed face for inspection. Neither
outer trim nor holes constrain future local sketch coordinates: geometry can
extend beyond the supporting face or across its holes.

Verification:

```sh
flutter test test/document/planar_support_test.dart test/cad_scene/selection
flutter analyze
flutter test
```
