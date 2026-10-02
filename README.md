# faust_cad_app_2

A Flutter CAD wireframe viewer.

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

`CadObject.build()` can return solids, shells, faces, wires, or edges. The scene
draws the linear edges of every shell boundary, including cavities and face holes,
in its existing wireframe style.
Surface filling and curved-edge rendering are not implemented. Face construction
validates topological closure; callers must ensure boundaries lie on the surface,
do not self-intersect, and contain their holes.
