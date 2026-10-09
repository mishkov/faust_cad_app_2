import 'package:faust_cad_app_2/planar_regions/planar_regions.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

PlanarCircle profileCircle(String id, double x, double y, double radius) =>
    PlanarCircle(id: id, center: Vector2(x, y), radius: radius);
PlanarSegment profileLine(String id, double x, double y, double u, double v) =>
    PlanarSegment(id: id, start: Vector2(x, y), end: Vector2(u, v));
List<PlanarInput> profileRectangle(
  String id,
  double x,
  double y,
  double width,
  double height,
) => [
  profileLine('$id:bottom', x, y, x + width, y),
  profileLine('$id:right', x + width, y, x + width, y + height),
  profileLine('$id:top', x + width, y + height, x, y + height),
  profileLine('$id:left', x, y + height, x, y),
];
RegionResult profileArrangement(Iterable<PlanarInput> inputs) =>
    const PlanarRegionEngine().build(inputs);
