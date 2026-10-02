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
```

`CadObject.build()` can return faces, wires, or edges. The scene draws the linear
edges of each boundary, including holes, in its existing wireframe style.
Surface filling and curved-edge rendering are not implemented. Face construction
validates topological closure; callers must ensure boundaries lie on the surface,
do not self-intersect, and contain their holes.
