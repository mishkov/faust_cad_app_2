import 'dart:typed_data';

import 'projected_face.dart';
import 'projected_face_index.dart';

enum TriangleCoverage { visible, hidden, partial, fallback }

/// Bounded convex subtraction in double precision, with interpolated RGBA.
///
/// One workspace is borrowed synchronously during a renderer paint. Only numbers
/// survive a call: projected faces and query results are released before return.
/// Results are valid until the next [resolve]; they are never a camera cache.
class CurvedTriangleVisibility {
  CurvedTriangleVisibility({
    this.maxFragments = 32,
    this.maxPolygonVertices = 24,
    this.maxFaceWork = 8192,
    this.maxFrameWork = 262144,
    this.maxCandidates = 256,
    this.maxOccluderVertices = 128,
  }) : assert(maxFragments > 0),
       assert(maxPolygonVertices >= 3),
       assert(maxFaceWork >= 0 && maxFrameWork >= 0),
       assert(maxCandidates > 0),
       _first = Float64List(maxFragments * maxPolygonVertices * stride),
       _second = Float64List(maxFragments * maxPolygonVertices * stride),
       _firstLengths = Int32List(maxFragments),
       _secondLengths = Int32List(maxFragments),
       _inside = Float64List(maxPolygonVertices * stride),
       _distances = Float64List(maxPolygonVertices),
       _nextInside = Float64List(maxPolygonVertices * stride),
       _outside = Float64List(maxPolygonVertices * stride);

  static const stride = 6;
  final int maxFragments, maxPolygonVertices;
  final int maxFaceWork, maxFrameWork, maxCandidates, maxOccluderVertices;
  final Float64List _first, _second, _inside, _nextInside, _outside, _distances;
  final Int32List _firstLengths, _secondLengths;
  final _candidates = <ProjectedFace>[];
  late Float64List _result;
  late Int32List _lengths;
  int fragmentCount = 0;
  int _faceWork = 0, _frameWork = 0;
  bool _exhausted = false;

  int get frameWork => _frameWork;
  int get retainedFaceCount => _candidates.length;
  int vertexCount(int fragment) => _lengths[fragment];
  double component(int fragment, int vertex, int channel) =>
      _result[(fragment * maxPolygonVertices + vertex) * stride + channel];

  void beginFrame() {
    _frameWork = 0;
    fragmentCount = 0;
    _candidates.clear();
  }

  /// Releases the current result without retaining any projected geometry.
  void endFrame() {
    fragmentCount = 0;
    _candidates.clear();
  }

  TriangleCoverage resolve(
    ProjectedFace face,
    ProjectedFaceIndex index, {
    required double bias,
    double? pixelScaleX,
    double pixelScaleY = 1,
    double pixelTranslateX = 0,
    double pixelTranslateY = 0,
  }) {
    fragmentCount = 0;
    _faceWork = 0;
    _exhausted = false;
    if (_frameWork >= maxFrameWork) return TriangleCoverage.fallback;
    final points = face.meshPoints, colors = face.meshColors;
    if (points == null ||
        colors == null ||
        points.length < 3 ||
        colors.length != points.length ||
        points.length - 2 > maxFragments) {
      return TriangleCoverage.fallback;
    }
    if (points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return TriangleCoverage.fallback;
    }
    // Start with the original fan triangles. A near-plane-clipped fan can have
    // a different affine colour field in each cell; preserve those boundaries.
    var current = _first, next = _second;
    var lengths = _firstLengths, nextLengths = _secondLengths;
    var count = points.length - 2;
    for (var i = 0; i < count; i++) {
      lengths[i] = 3;
      for (var j = 0; j < 3; j++) {
        final source = j == 0 ? 0 : i + j;
        final offset = (i * maxPolygonVertices + j) * stride;
        final color = colors[source].toARGB32();
        current[offset] = points[source].dx;
        current[offset + 1] = points[source].dy;
        current[offset + 2] = ((color >> 16) & 255).toDouble();
        current[offset + 3] = ((color >> 8) & 255).toDouble();
        current[offset + 4] = (color & 255).toDouble();
        current[offset + 5] = ((color >> 24) & 255).toDouble();
      }
    }
    var changed = false, hasMaskCandidate = false;
    try {
      if (!index.queryInto(face.bounds, _candidates, limit: maxCandidates)) {
        return TriangleCoverage.fallback;
      }
      for (final occluder in _candidates) {
        if (identical(occluder, face)) continue;
        final a = occluder.inverseDepth.x - face.inverseDepth.x;
        final b = occluder.inverseDepth.y - face.inverseDepth.y;
        final c = occluder.inverseDepth.z - face.inverseDepth.z - bias;
        final bounds = occluder.bounds;
        final dx = a * (a >= 0 ? bounds.right : bounds.left);
        final dy = b * (b >= 0 ? bounds.bottom : bounds.top);
        final tolerance = (dx.abs() + dy.abs() + c.abs()) * 1e-6;
        if (dx + dy + c < -tolerance) continue;
        // Bound convexity validation too; large/trimmed contours retain masks.
        if (occluder.contours.length != 1 ||
            occluder.contours.single.length > maxOccluderVertices ||
            !a.isFinite ||
            !b.isFinite ||
            !c.isFinite) {
          return TriangleCoverage.fallback;
        }
        hasMaskCandidate = true;
        final planes = occluder.convexBoundary;
        if (planes == null) {
          return TriangleCoverage.fallback;
        }
        var outputCount = 0;
        for (var fragment = 0; fragment < count; fragment++) {
          final offset = fragment * maxPolygonVertices * stride;
          final length = lengths[fragment];
          // Test the actual intersection first. This prevents fragments from
          // multiplying when only the broad-phase bounds overlap.
          _inside.setRange(0, length * stride, current, offset);
          var insideLength = length;
          for (var plane = -1; plane < planes.length; plane++) {
            final x = plane < 0 ? a : planes[plane].x;
            final y = plane < 0 ? b : planes[plane].y;
            final z = plane < 0 ? c : planes[plane].z;
            insideLength = _clip(
              _inside,
              insideLength,
              _nextInside,
              x,
              y,
              z,
              true,
            );
            if (_exhausted) return TriangleCoverage.fallback;
            if (insideLength < 3) break;
            _inside.setRange(0, insideLength * stride, _nextInside);
          }
          if (insideLength < 3) {
            if (outputCount >= maxFragments) return TriangleCoverage.fallback;
            next.setRange(
              outputCount * maxPolygonVertices * stride,
              outputCount * maxPolygonVertices * stride + length * stride,
              current,
              offset,
            );
            nextLengths[outputCount++] = length;
            continue;
          }
          changed = true;
          _inside.setRange(0, length * stride, current, offset);
          insideLength = length;
          // P \ (H0 ∩ ... ∩ Hn) is the disjoint union of outside strips.
          // The remaining inside polygon is discarded after the last plane.
          for (var plane = -1; plane < planes.length; plane++) {
            final x = plane < 0 ? a : planes[plane].x;
            final y = plane < 0 ? b : planes[plane].y;
            final z = plane < 0 ? c : planes[plane].z;
            final outsideLength = _clip(
              _inside,
              insideLength,
              _outside,
              x,
              y,
              z,
              false,
            );
            final newInsideLength = _clip(
              _inside,
              insideLength,
              _nextInside,
              x,
              y,
              z,
              true,
            );
            if (_exhausted) return TriangleCoverage.fallback;
            if (outsideLength >= 3) {
              if (outputCount >= maxFragments) return TriangleCoverage.fallback;
              final target = outputCount * maxPolygonVertices * stride;
              next.setRange(target, target + outsideLength * stride, _outside);
              nextLengths[outputCount++] = outsideLength;
            }
            insideLength = newInsideLength;
            if (insideLength < 3) break;
            _inside.setRange(0, insideLength * stride, _nextInside);
          }
        }
        count = outputCount;
        final old = current;
        current = next;
        next = old;
        final oldLengths = lengths;
        lengths = nextLengths;
        nextLengths = oldLengths;
        if (count == 0) {
          if (pixelScaleX != null) {
            for (var i = 0; i < points.length; i++) {
              final p = points[i], q = points[(i + 1) % points.length];
              if (_uncertainEdge(
                p.dx * pixelScaleX + pixelTranslateX,
                p.dy * pixelScaleY + pixelTranslateY,
                q.dx * pixelScaleX + pixelTranslateX,
                q.dy * pixelScaleY + pixelTranslateY,
              )) {
                return TriangleCoverage.fallback;
              }
            }
          }
          return TriangleCoverage.hidden;
        }
      }
      _result = current;
      _lengths = lengths;
      if ((changed || hasMaskCandidate) && pixelScaleX != null) {
        for (var f = 0; f < count; f++) {
          for (var v = 0; v < lengths[f]; v++) {
            final p = (f * maxPolygonVertices + v) * stride;
            final q = (f * maxPolygonVertices + (v + 1) % lengths[f]) * stride;
            if (_uncertainEdge(
              current[p] * pixelScaleX + pixelTranslateX,
              current[p + 1] * pixelScaleY + pixelTranslateY,
              current[q] * pixelScaleX + pixelTranslateX,
              current[q + 1] * pixelScaleY + pixelTranslateY,
            )) {
              return TriangleCoverage.fallback;
            }
          }
        }
      }
      fragmentCount = count;
      return changed ? TriangleCoverage.partial : TriangleCoverage.visible;
    } finally {
      // Release references even on budget exhaustion or invalid input.
      _candidates.clear();
    }
  }

  // Paths and triangle fills can choose different coverage at subpixel
  // contacts. Retain the original isolated mask if a boundary approaches a
  // device pixel centre. Walk the major axis, bounded by the same work budget.
  bool _uncertainEdge(double px, double py, double qx, double qy) {
    const radius = 1 / 8;
    if ((qx - px).abs() < (qy - py).abs()) {
      final old = px;
      px = py;
      py = old;
      final oldQ = qx;
      qx = qy;
      qy = oldQ;
    }
    if (px > qx) {
      final x = px, y = py;
      px = qx;
      py = qy;
      qx = x;
      qy = y;
    }
    final dx = qx - px, dy = qy - py;
    if (dx < 1e-12) return false;
    final tolerance = radius * (1 + (dy / dx).abs());
    final start = (px - radius - 0.5).ceil(), end = (qx + radius - 0.5).floor();
    for (var column = start; column <= end; column++) {
      if (_faceWork >= maxFaceWork || _frameWork >= maxFrameWork) {
        _exhausted = true;
        return true;
      }
      _faceWork++;
      _frameWork++;
      final t = ((column + 0.5 - px) / dx).clamp(0.0, 1.0);
      final y = py + dy * t;
      if ((y - ((y - 0.5).round() + 0.5)).abs() <= tolerance) return true;
    }
    return false;
  }

  int _clip(
    Float64List input,
    int length,
    Float64List output,
    double a,
    double b,
    double c,
    bool inside,
  ) {
    if (_faceWork + length > maxFaceWork ||
        _frameWork + length > maxFrameWork) {
      _exhausted = true;
      return 0;
    }
    _faceWork += length;
    _frameWork += length;
    var accepted = 0;
    for (var vertex = 0; vertex < length; vertex++) {
      final offset = vertex * stride;
      final d = a * input[offset] + b * input[offset + 1] + c;
      _distances[vertex] = d;
      if (inside ? d > 0 : d <= 0) accepted++;
    }
    if (accepted == 0) return 0;
    if (accepted == length) {
      output.setRange(0, length * stride, input);
      return length;
    }
    var written = 0;
    var previous = (length - 1) * stride;
    var previousDistance = _distances[length - 1];
    for (var vertex = 0; vertex < length; vertex++) {
      final offset = vertex * stride;
      final distance = _distances[vertex];
      // Strict positive nearer depth matches the existing erase masks. The
      // complementary side includes equality, retaining coplanar geometry.
      final keep = inside ? distance > 0 : distance <= 0;
      final keepPrevious = inside
          ? previousDistance > 0
          : previousDistance <= 0;
      if (keep != keepPrevious) {
        if (written >= maxPolygonVertices) {
          _exhausted = true;
          return 0;
        }
        final t = previousDistance / (previousDistance - distance);
        for (var channel = 0; channel < stride; channel++) {
          output[written * stride + channel] =
              input[previous + channel] +
              (input[offset + channel] - input[previous + channel]) * t;
        }
        written++;
      }
      if (keep) {
        if (written >= maxPolygonVertices) {
          _exhausted = true;
          return 0;
        }
        output.setRange(
          written * stride,
          (written + 1) * stride,
          input,
          offset,
        );
        written++;
      }
      previous = offset;
      previousDistance = distance;
    }
    return written;
  }
}
