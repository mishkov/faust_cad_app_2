import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_objects/ground_grid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/cad_primitive.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/extrusion/analytic_extrusion_service.dart';
import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;

// Circle crossed by an open polyline, matching the reported partial extrusion.
SketchGeometry orbitSketch() {
  final positions = [
    (36.44940039613595, 24.497316132269596),
    (9.858963653249617, 102.19151991633728),
    (9.858963653249617, -100.4516796684142),
    (110.48323141345074, -100.4516796684142),
    (110.48323141345074, 10.54323066281091),
    (-63.97385706297569, 10.54323066281091),
  ];
  final sketch = SketchDefinition(
    support: const PlanarSupport.principal(PrincipalPlane.xy),
    points: [
      for (var i = 0; i < positions.length; i++)
        SketchPoint(
          id: SketchEntityId('p$i'),
          x: positions[i].$1,
          y: positions[i].$2,
        ),
    ],
    segments: [
      for (var i = 1; i < positions.length - 1; i++)
        SketchLineSegment(
          id: SketchEntityId('line$i'),
          startPointId: SketchEntityId('p$i'),
          endPointId: SketchEntityId('p${i + 1}'),
        ),
    ],
    circles: [
      SketchCircle(
        id: SketchEntityId('circle'),
        centerPointId: SketchEntityId('p0'),
        radius: 57.9404077810148,
      ),
    ],
  );
  return SketchGeometry(definition: sketch, frame: PlanarFrame.xy());
}

List<CadPrimitive> orbitGeometry(SketchGeometry sketch) {
  final regions = const PlanarRegionEngine().build(
    const SketchPlanarAdapter().adaptSolved(sketch.solved),
  );
  final chosen = regions.regions.singleWhere(
    (r) => r.locate(Vector2(0, 30)) == RegionPointLocation.inside,
  );
  final result = const AnalyticExtrusionService().extrude(
    regions: regions,
    regionIds: [chosen.id],
    frame: sketch.frame,
    distance: 10,
  );
  if (!result.isValid) {
    throw StateError(
      'Invalid fixture: ${result.diagnostics.map((d) => d.message)}',
    );
  }
  return [
    ...GroundGrid(100, 100).build(),
    ...Cylinder(
      frame: PlanarFrame.xy(origin: Vector3(60, 60, 0)),
      radius: 8,
      height: 15,
    ).build(),
    ...Cube(centerPosition: Vertex(Vector3(15, 16, 19)), size: 20).build(),
    ...Cube(centerPosition: Vertex(Vector3(40, 16, 15)), size: 30).build(),
    ...result.solids,
  ];
}
