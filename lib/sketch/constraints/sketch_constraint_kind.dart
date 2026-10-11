/// The supported persistent relations and their ordered reference roles.
enum SketchConstraintKind {
  coincident, // point, point.
  pointOnLine, // point, segment (supporting infinite line).
  pointOnCircle, // point, circle.
  horizontal, // segment.
  vertical, // segment.
  parallel, // segment, segment.
  perpendicular, // segment, segment.
  lineLength, // segment; value: length.
  distance, // point, point; value: distance.
  radius, // circle; value: radius.
  diameter, // circle; value: diameter.
  equalLengths, // segment, segment.
  equalRadii, // circle, circle.
  fixedPoint, // point; values: x, y.
  fixedPrimitive, // segment: x1,y1,x2,y2; circle: cx,cy,r.
}
