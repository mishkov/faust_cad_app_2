import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/sketch/sketch.dart';
import 'package:flutter_test/flutter_test.dart';

SketchEntityId eid(String value) => SketchEntityId(value);
SketchPoint p(String id, double x, double y) =>
    SketchPoint(id: eid(id), x: x, y: y);
SketchLineSegment l(String id, String a, String b) =>
    SketchLineSegment(id: eid(id), startPointId: eid(a), endPointId: eid(b));
SketchCircle circle(String id, String center, double radius) =>
    SketchCircle(id: eid(id), centerPointId: eid(center), radius: radius);
SketchConstraint c(
  String id,
  SketchConstraintKind kind,
  List<String> refs, [
  List<double> values = const [],
]) => SketchConstraint(
  id: SketchConstraintId(id),
  kind: kind,
  references: refs.map(eid),
  values: values,
);
SketchDefinition sketch({
  List<SketchPoint> points = const [],
  List<SketchLineSegment> lines = const [],
  List<SketchCircle> circles = const [],
  List<SketchConstraint> constraints = const [],
}) => SketchDefinition(
  support: const PlanarSupport.principal(PrincipalPlane.xy),
  points: points,
  segments: lines,
  circles: circles,
  constraints: constraints,
);
const solver = SketchSolver();
double distance(SolvedSketch s, String a, String b) =>
    (s.points[eid(a)]!.position - s.points[eid(b)]!.position).length;
void at(
  SolvedSketch s,
  String id,
  double x,
  double y, [
  double tolerance = 1e-7,
]) {
  expect(s.points[eid(id)]!.x, closeTo(x, tolerance), reason: '$id.x');
  expect(s.points[eid(id)]!.y, closeTo(y, tolerance), reason: '$id.y');
}
