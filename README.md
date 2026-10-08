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
fills planar faces with opaque gray, adds black visible boundary edges, and
uses ambient plus directional lighting fixed above and to the camera's right.
Faces render from either side. Trimming holes stay open, revealing geometry
behind them. Depth comparisons hide obscured faces and edges across all objects,
including standalone wires and grid lines, independently of object order.
Intersecting faces are clipped by their local perspective depth rather than
sorted as whole objects. Both modes clip geometry to the camera view frustum.

The current renderer supports `PlaneSurface` faces bounded by `LinearCadCurve`
edges. Curved surfaces and curved edges need tessellation before they can be
rendered. Shading describes surface illumination; cast shadows are not rendered.

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
other curves must share their curve instance. Each face must visit a boundary
vertex only once, and faces around each vertex must form one connected fan, so
skins touching at only a vertex are rejected. Solid construction requires this
closed manifold topology. Geometric volume enclosure,
non-zero volume, self-intersection, cavity containment, and outward/inward
surface orientation remain the caller's responsibility.

`CadObject.build()` can return solids, shells, faces, wires, or edges. Frame mode
draws the linear edges of every shell boundary, including cavities and face holes;
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
