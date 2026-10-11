import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';

SketchEntityId entityId(String value) => SketchEntityId(value);

SketchDefinition rectangleSketch({
  PlanarSupport support = const PlanarSupport.principal(PrincipalPlane.xy),
  double width = 4,
  bool circle = false,
}) => SketchDefinition(
  support: support,
  points: [
    SketchPoint(id: entityId('p0'), x: 0, y: 0),
    SketchPoint(id: entityId('p1'), x: width, y: 0),
    SketchPoint(id: entityId('p2'), x: width, y: 3),
    SketchPoint(id: entityId('p3'), x: 0, y: 3),
    if (circle) SketchPoint(id: entityId('center'), x: 2, y: 1.5),
  ],
  segments: [
    for (var i = 0; i < 4; i++)
      SketchLineSegment(
        id: entityId('line$i'),
        startPointId: entityId('p$i'),
        endPointId: entityId('p${(i + 1) % 4}'),
      ),
  ],
  circles: [
    if (circle)
      SketchCircle(
        id: entityId('circle'),
        centerPointId: entityId('center'),
        radius: 0.5,
      ),
  ],
);
