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

The topology hierarchy is `Shell → Face → Wire → Edge → Vertex`. Shells preserve
the supplied face references, so surfaces, wires, edges, and vertices can be
shared without duplicating their geometry. A cube's six connected faces form a
closed shell; removing one face creates an open shell. Both are supported.
Shell construction validates connectivity; volume enclosure, manifoldness, and
consistent face orientation are the caller's responsibility. A closed shell can
serve as the boundary of a future solid primitive.

`CadObject.build()` can return shells, faces, wires, or edges. The scene draws the
linear edges of each boundary, including holes, in its existing wireframe style.
Surface filling and curved-edge rendering are not implemented. Face construction
validates topological closure; callers must ensure boundaries lie on the surface,
do not self-intersect, and contain their holes.
