import 'dart:convert';
import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' show Vector2;

import '../../cad_scene/geometry/geometry_tolerance.dart';
import '../boundary_portion.dart';
import '../boundary_source.dart';
import '../planar_circle.dart';
import '../planar_input.dart';
import '../planar_region.dart';
import '../planar_segment.dart';
import '../region_diagnostic.dart';
import '../region_loop.dart';
import '../region_result.dart';
import '../region_selection.dart';
import 'predicates.dart' as exact;

// These private graph records share one library so its mutable construction
// state cannot escape into the immutable public geometry API.
const _tau = 2 * math.pi;
const _roundoff = 64 * 2.220446049250313e-16;

double _cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;
double _angle(Vector2 d) => math.atan2(d.y, d.x) % _tau;

class _Node {
  _Node(this.point, this.index);
  final Vector2 point;
  final int index;
  _Node? parent;
  _Node get root {
    if (parent == null) return this;
    return parent = parent!.root;
  }
}

class _Cut {
  _Cut(this.parameter, this.node);
  final double parameter;
  final _Node node;
}

class _Curve {
  _Curve.line(this.input, this.a, this.b) : center = null, radius = null;
  _Curve.circle(this.input, Vector2 c, double r)
    : a = c,
      b = c,
      center = c,
      radius = r;
  final PlanarInput input;
  final Vector2 a, b;
  final Vector2? center;
  final double? radius;
  final cuts = <_Cut>[];
  final aliases = <_Curve>[];
  bool get isCircle => center != null;
  Vector2 at(double t) => isCircle
      ? center! + Vector2(math.cos(t), math.sin(t)) * radius!
      : a + (b - a) * t;
  double parameter(Vector2 p) =>
      isCircle ? _angle(p - center!) : (p - a).dot(b - a) / (b - a).length2;
}

class _Edge {
  _Edge(this.index, this.curve, this.t0, this.t1, this.a, this.b, this.sources);
  final int index;
  final _Curve curve;
  final double t0, t1;
  final _Node a, b;
  final List<BoundarySource> sources;
  bool bridge = false;
}

class _Half {
  _Half(this.edge, this.forward);
  final _Edge edge;
  final bool forward;
  late _Half twin;
  _Node get start => (forward ? edge.a : edge.b).root;
  _Node get end => (forward ? edge.b : edge.a).root;
  double get t0 => forward ? edge.t0 : edge.t1;
  double get t1 => forward ? edge.t1 : edge.t0;
  Vector2 get tangent =>
      edge.curve.isCircle
            ? Vector2(-math.sin(t0), math.cos(t0)) * (forward ? 1.0 : -1.0)
            : (forward
                  ? edge.curve.b - edge.curve.a
                  : edge.curve.a - edge.curve.b)
        ..normalize();
  double get curvature =>
      edge.curve.isCircle ? (forward ? 1 : -1) / edge.curve.radius! : 0;
  String get key => '${edge.index}:${forward ? 1 : 0}';
}

class _Cycle {
  _Cycle(this.halves, this.loop);
  final List<_Half> halves;
  final RegionLoop loop;
  final holes = <_Cycle>[];
  PlanarRegion? region;
}

/// Internal mutable arrangement builder; public results contain immutable values.
class Arrangement {
  Arrangement(Iterable<PlanarInput> inputs, this.tolerance)
    : inputs = inputs.toList()..sort((a, b) => a.id.compareTo(b.id)) {
    if (this.inputs.map((i) => i.id).toSet().length != this.inputs.length) {
      throw ArgumentError('Input IDs must be unique');
    }
    if (this.inputs.any((i) => i is! PlanarCircle && i is! PlanarSegment)) {
      throw ArgumentError('Only PlanarSegment and PlanarCircle are supported');
    }
  }
  final List<PlanarInput> inputs;
  final GeometryTolerance tolerance;
  final diagnostics = <RegionDiagnostic>[];
  final curves = <_Curve>[];
  final nodes = <_Node>[];
  final edges = <_Edge>[];
  final halves = <_Half>[];
  final cells = <_Cycle>[];
  Vector2 origin = Vector2.zero();
  double scale = 1;

  RegionResult build() {
    _prepare();
    for (var i = 0; i < curves.length; i++) {
      for (var j = i + 1; j < curves.length; j++) {
        _intersect(curves[i], curves[j]);
      }
    }
    _split();
    if (!diagnostics.any((d) => d.isError)) {
      _markBridges();
      for (final e in edges.where((e) => !e.bridge)) {
        final a = _Half(e, true), b = _Half(e, false);
        a.twin = b;
        b.twin = a;
        halves.addAll([a, b]);
      }
      cells.addAll(_classify(_walk(halves)));
    }
    if (diagnostics.any((d) => d.isError)) cells.clear();
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      c.region = PlanarRegion(
        id: 'region:$i',
        outer: c.loop,
        holes: c.holes.map((h) => h.loop),
      );
    }
    for (final cell in cells) {
      if (!cell.region!.area.isFinite || cell.region!.area <= 0) {
        _diagnose(
          'numericRange',
          'Material area cannot be resolved in model units.',
          cell.halves.map((h) => h.edge.curve),
          error: true,
        );
      }
    }
    if (diagnostics.any((d) => d.isError)) cells.clear();
    diagnostics.sort(
      (a, b) => '${a.code}:${a.inputIds}'.compareTo('${b.code}:${b.inputIds}'),
    );
    return RegionResult(
      regions: cells.map((c) => c.region!),
      diagnostics: diagnostics,
      select: _union,
    );
  }

  void _diagnose(
    String code,
    String message,
    Iterable<_Curve> affected, {
    bool error = false,
  }) {
    final ids =
        affected
            .expand((c) => [c.input.id, ...c.aliases.map((a) => a.input.id)])
            .toSet()
            .toList()
          ..sort();
    diagnostics.add(RegionDiagnostic(code, message, ids, isError: error));
  }

  final Map<_Node, Vector2> _originalEndpoints = {};
  final Map<_Node, Vector2> _originalSeams = {};

  _Node _seam(Vector2 normalized, Vector2 original) {
    final node = _node(normalized);
    _originalSeams[node] = original;
    return node;
  }

  bool _containsExact(_Curve curve, Vector2 point) {
    if (curve.input case final PlanarSegment line) {
      return exact.orientation(line.start, line.end, point) == 0 &&
          exact.boundsMeet(line.start, line.end, point, point);
    }
    final circle = curve.input as PlanarCircle;
    return exact.circleContacts(point, 0, circle.center, circle.radius).$1 == 0;
  }

  _Node _endpoint(Vector2 normalized, Vector2 original, _Curve curve) {
    for (final entry in _originalEndpoints.entries) {
      if (entry.value == original) return entry.key;
      if (entry.key.point == normalized) {
        _diagnose(
          'numericRange',
          'Distinct original endpoints became indistinguishable during normalization.',
          [curve],
          error: true,
        );
      }
    }
    final node = _node(normalized);
    _originalEndpoints[node] = original.clone();
    return node;
  }

  _Node _node(Vector2 p) {
    // Synthetic seams and independently constructed events get distinct nodes.
    // Only proven incidence on a participating curve can join those nodes.
    final n = _Node(p, nodes.length);
    nodes.add(n);
    return n;
  }

  void _join(_Node a, _Node b) {
    a = a.root;
    b = b.root;
    if (a.index < b.index) {
      b.parent = a;
    } else if (a.index > b.index) {
      a.parent = b;
    }
  }

  final _normalizedX = <double, (double, String)>{};
  final _normalizedY = <double, (double, String)>{};
  Vector2 _normalize(Vector2 point, String id) {
    final normalized = (point - origin) / scale;
    for (final axis in [
      (normalized.x, point.x, _normalizedX),
      (normalized.y, point.y, _normalizedY),
    ]) {
      final previous = axis.$3[axis.$1];
      if (previous != null && previous.$1 != axis.$2) {
        diagnostics.add(
          RegionDiagnostic(
            'numericRange',
            'Distinct coordinate values became indistinguishable during normalization.',
            [id, previous.$2]..sort(),
            isError: true,
          ),
        );
      }
      axis.$3[axis.$1] = (axis.$2, id);
    }
    return normalized;
  }

  void _prepare() {
    if (inputs.isEmpty) return;
    origin = switch (inputs.first) {
      PlanarSegment s => s.start,
      PlanarCircle c => c.center,
      _ => throw StateError('Unsupported input'),
    };
    var extent = 0.0;
    for (final input in inputs) {
      if (input is PlanarSegment) {
        extent = math.max(
          extent,
          math.max((input.start - origin).length, (input.end - origin).length),
        );
      } else if (input is PlanarCircle) {
        extent = math.max(
          extent,
          (input.center - origin).length + input.radius,
        );
      }
    }
    if (!extent.isFinite) {
      diagnostics.add(
        RegionDiagnostic(
          'numericRange',
          'Coordinate extent exceeds finite arithmetic.',
          inputs.map((i) => i.id),
          isError: true,
        ),
      );
      return;
    }
    scale = extent == 0 ? 1 : extent;
    for (final input in inputs) {
      final _Curve c;
      if (input is PlanarSegment) {
        if (input.start == input.end) {
          diagnostics.add(
            RegionDiagnostic(
              'zeroLength',
              'Zero-length segment contributes no boundary.',
              [input.id],
            ),
          );
          continue;
        }
        c = _Curve.line(
          input,
          _normalize(input.start, input.id),
          _normalize(input.end, input.id),
        );
        if ((c.b - c.a).length == 0 ||
            !(c.b - c.a).length2.isFinite ||
            (c.b - c.a).length2 == 0) {
          _diagnose(
            'numericRange',
            'Segment cannot be resolved at this model extent.',
            [c],
            error: true,
          );
          continue;
        }
        if ((input.end - input.start).length <= tolerance.distance) {
          _diagnose(
            'tinyGeometry',
            'Small segment is retained without snapping.',
            [c],
          );
        }
        c.cuts.addAll([
          _Cut(0, _endpoint(c.a, input.start, c)),
          _Cut(1, _endpoint(c.b, input.end, c)),
        ]);
      } else if (input is PlanarCircle) {
        c = _Curve.circle(
          input,
          _normalize(input.center, input.id),
          input.radius / scale,
        );
        if (c.radius == 0 ||
            c.radius! * c.radius! == 0 ||
            c.center! + Vector2(c.radius!, 0) == c.center) {
          _diagnose(
            'numericRange',
            'Circle cannot be resolved at this model extent.',
            [c],
            error: true,
          );
          continue;
        }
        if (input.radius <= tolerance.distance) {
          _diagnose('tinyGeometry', 'Small circle is retained analytically.', [
            c,
          ]);
        }
        final duplicate = curves
            .where(
              (d) =>
                  d.input is PlanarCircle &&
                  (d.input as PlanarCircle).center == input.center &&
                  (d.input as PlanarCircle).radius == input.radius,
            )
            .firstOrNull;
        if (duplicate != null) {
          duplicate.aliases.add(c);
          _diagnose(
            'coincidentCircle',
            'Coincident circles share boundaries and retain every source ID.',
            [duplicate],
          );
          continue;
        }
        c.cuts.addAll([
          _Cut(
            0,
            _seam(
              c.center! + Vector2(c.radius!, 0),
              input.center + Vector2(input.radius, 0),
            ),
          ),
          _Cut(
            math.pi,
            _seam(
              c.center! - Vector2(c.radius!, 0),
              input.center - Vector2(input.radius, 0),
            ),
          ),
        ]);
      } else {
        continue;
      }
      curves.add(c);
    }
  }

  void _hit(_Curve a, double ta, _Curve b, double tb, Vector2 p) {
    if (a.isCircle) ta %= _tau;
    if (b.isCircle) tb %= _tau;
    if ((!a.isCircle && (ta < 0 || ta > 1)) ||
        (!b.isCircle && (tb < 0 || tb > 1))) {
      return;
    }
    _Node? endpoint(_Curve c, double t) {
      for (final cut in c.cuts) {
        if (cut.parameter == t) {
          final witness =
              _originalEndpoints[cut.node] ??
              _originalSeams[cut.node] ??
              cut.node.point * scale + origin;
          if (cut.node.point != p &&
              !(_containsExact(a, witness) && _containsExact(b, witness))) {
            _diagnose(
              'numericAmbiguity',
              'Independent event coordinates disagree at the same curve parameter.',
              [a, b],
              error: true,
            );
          }
          return cut.node;
        }
      }
      return null;
    }

    final na = endpoint(a, ta), nb = endpoint(b, tb);
    final n = na ?? nb ?? _node(p);
    if (na != null) _join(n, na);
    if (nb != null) _join(n, nb);
    a.cuts.add(_Cut(ta, n));
    b.cuts.add(_Cut(tb, n));
  }

  void _intersect(_Curve a, _Curve b) {
    if (a.isCircle && b.isCircle) {
      _circles(a, b);
      return;
    }
    if (a.isCircle || b.isCircle) {
      _lineCircle(a.isCircle ? b : a, a.isCircle ? a : b);
      return;
    }
    final originalA = a.input as PlanarSegment,
        originalB = b.input as PlanarSegment;
    if (!exact.segmentsMeet(
      originalA.start,
      originalA.end,
      originalB.start,
      originalB.end,
    )) {
      return;
    }
    final d = a.b - a.a, e = b.b - b.a, offset = b.a - a.a;
    final den = _cross(d, e);
    final parallel =
        exact.directionCross(
          originalA.start,
          originalA.end,
          originalB.start,
          originalB.end,
        ) ==
        0;
    if (parallel) {
      if (_cross(offset, d) != 0 || den != 0) {
        _diagnose(
          'numericAmbiguity',
          'Collinearity was lost during normalization.',
          [a, b],
          error: true,
        );
        return;
      }
      var overlap = false;
      for (final p in [a.a, a.b, b.a, b.b]) {
        final ta = a.parameter(p), tb = b.parameter(p);
        if (ta >= 0 && ta <= 1 && tb >= 0 && tb <= 1) {
          _hit(a, ta, b, tb, p);
          overlap = true;
        }
      }
      if (overlap) {
        _diagnose(
          'overlappingSegment',
          'Collinear overlap is split and deduplicated with all source intervals.',
          [a, b],
        );
      }
      return;
    }
    if (den.abs() <= _roundoff * d.length * e.length) {
      _diagnose(
        'numericAmbiguity',
        'Intersecting line directions are too close to parallel to construct safely.',
        [a, b],
        error: true,
      );
      return;
    }
    // Exact endpoint incidence takes precedence over rounded intersection parameters.
    for (final pair in [
      (originalA.start, a, 0.0, b, originalB),
      (originalA.end, a, 1.0, b, originalB),
      (originalB.start, b, 0.0, a, originalA),
      (originalB.end, b, 1.0, a, originalA),
    ]) {
      if (exact.orientation(pair.$5.start, pair.$5.end, pair.$1) == 0 &&
          exact.boundsMeet(pair.$1, pair.$1, pair.$5.start, pair.$5.end)) {
        final point = pair.$3 == 0 ? pair.$2.a : pair.$2.b;
        _hit(pair.$2, pair.$3, pair.$4, pair.$4.parameter(point), point);
        return;
      }
    }
    final ta = _cross(offset, e) / den, tb = _cross(offset, d) / den;
    if (ta <= 0 || ta >= 1 || tb <= 0 || tb >= 1) {
      _diagnose(
        'numericAmbiguity',
        'Interior intersection rounded onto or beyond an endpoint.',
        [a, b],
        error: true,
      );
      return;
    }
    _hit(a, ta, b, tb, a.at(ta));
  }

  void _lineCircle(_Curve line, _Curve circle) {
    final d = line.b - line.a, offset = line.a - circle.center!;
    final length = d.length;
    final direction = d / length;
    final along = -offset.dot(direction),
        perpendicular = _cross(offset, direction);
    final h2 = circle.radius! * circle.radius! - perpendicular * perpendicular;
    final originalLine = line.input as PlanarSegment,
        originalCircle = circle.input as PlanarCircle;
    final contact = exact.lineCircleContact(
      originalLine.start,
      originalLine.end,
      originalCircle.center,
      originalCircle.radius,
    );
    if (contact < 0) return;
    if (contact > 0 && h2 <= 0) {
      _diagnose(
        'numericAmbiguity',
        'Line/circle construction disagrees with exact contact classification.',
        [line, circle],
        error: true,
      );
      return;
    }
    if (contact > 0 &&
        h2.abs() <= _roundoff * circle.radius! * circle.radius!) {
      final t = along / length;
      if (t >= 0 && t <= 1) {
        _diagnose(
          'numericAmbiguity',
          'Line/circle contact is too close to tangency to classify safely.',
          [line, circle],
          error: true,
        );
      }
      return;
    }
    final h = contact == 0 ? 0.0 : math.sqrt(h2);
    if (h == 0 && (along < 0 || along > length)) return;
    if (h == 0) {
      _diagnose(
        'tangency',
        'Line/circle tangent contact is retained as a vertex.',
        [line, circle],
      );
    }
    for (final distance in h == 0 ? [along] : [along - h, along + h]) {
      final t = distance / length;
      if (t < 0 || t > 1) continue;
      final p = line.at(t);
      _hit(line, t, circle, circle.parameter(p), p);
    }
  }

  void _circles(_Curve a, _Curve b) {
    final delta = b.center! - a.center!, distance = delta.length;
    final ra = a.radius!, rb = b.radius!;
    final originalA = a.input as PlanarCircle,
        originalB = b.input as PlanarCircle;
    final contact = exact.circleContacts(
      originalA.center,
      originalA.radius,
      originalB.center,
      originalB.radius,
    );
    if (contact.$1 > 0 || contact.$2 < 0) return;
    if (distance == 0) {
      _diagnose(
        'numericRange',
        'Distinct circle centers became indistinguishable.',
        [a, b],
        error: true,
      );
      return;
    }
    final outerResidual = distance - (ra + rb);
    final innerResidual = distance - (ra - rb).abs();
    final tangent = contact.$1 == 0 || contact.$2 == 0;
    if (!tangent &&
        (outerResidual >= 0 ||
            innerResidual <= 0 ||
            outerResidual.abs() <= _roundoff * math.max(distance, ra + rb) ||
            innerResidual.abs() <=
                _roundoff * math.max(distance, (ra - rb).abs()))) {
      _diagnose(
        'numericAmbiguity',
        'Circle construction is too close to tangency to classify safely.',
        [a, b],
        error: true,
      );
      return;
    }
    final along = tangent
        ? (contact.$1 == 0 || ra > rb ? ra : -ra)
        : (distance * distance + (ra - rb) * (ra + rb)) / (2 * distance);
    final h2 = ra * ra - along * along;
    if (!tangent && h2 <= 0) {
      _diagnose(
        'numericAmbiguity',
        'Circle intersections are below arithmetic resolution.',
        [a, b],
        error: true,
      );
      return;
    }
    final direction = delta / distance, base = a.center! + direction * along;
    final h = tangent ? 0.0 : math.sqrt(h2);
    if (tangent) {
      _diagnose(
        'tangency',
        'Circle tangent contact is retained; point-only unions are rejected.',
        [a, b],
      );
    }
    for (final p
        in h == 0
            ? [base]
            : [
                base + Vector2(-direction.y, direction.x) * h,
                base - Vector2(-direction.y, direction.x) * h,
              ]) {
      _hit(a, a.parameter(p), b, b.parameter(p), p);
    }
  }

  void _split() {
    for (final c in curves) {
      c.cuts.sort((a, b) => a.parameter.compareTo(b.parameter));
      final cuts = <_Cut>[];
      for (final cut in c.cuts) {
        if (cuts.isNotEmpty && cut.parameter == cuts.last.parameter) {
          _join(cut.node, cuts.last.node);
          continue;
        }
        if (cuts.isNotEmpty &&
            (cut.parameter - cuts.last.parameter).abs() <=
                _roundoff * math.max(1, cut.parameter.abs())) {
          // Events computed by independent pairs can differ by a few ULPs.
          // Never collapse two independent original endpoints or distinct hits.
          if (cut.node.root == cuts.last.node.root) continue;
          _diagnose(
            'numericAmbiguity',
            'Distinct boundary events are too close to order safely.',
            [c],
            error: true,
          );
        }
        cuts.add(cut);
      }
      if (c.isCircle && cuts.isNotEmpty) {
        cuts.add(_Cut(cuts.first.parameter + _tau, cuts.first.node));
      }
      for (var i = 1; i < cuts.length; i++) {
        final a = cuts[i - 1], b = cuts[i];
        if (a.node.root == b.node.root) {
          _diagnose(
            'numericAmbiguity',
            'A nonzero portion collapsed to one vertex.',
            [c],
            error: true,
          );
          continue;
        }
        final sources = [
          BoundarySource(c.input.id, a.parameter, b.parameter),
          ...c.aliases.map(
            (d) => BoundarySource(d.input.id, a.parameter, b.parameter),
          ),
        ];
        _Edge? duplicate;
        if (!c.isCircle) {
          duplicate = edges
              .where(
                (e) =>
                    !e.curve.isCircle &&
                    ((e.a.root == a.node.root && e.b.root == b.node.root) ||
                        (e.b.root == a.node.root && e.a.root == b.node.root)),
              )
              .firstOrNull;
        }
        if (duplicate == null) {
          edges.add(
            _Edge(
              edges.length,
              c,
              a.parameter,
              b.parameter,
              a.node,
              b.node,
              sources,
            ),
          );
        } else {
          duplicate.sources.addAll(
            duplicate.a.root == a.node.root
                ? sources
                : sources.map((s) => s.reversed()),
          );
        }
      }
    }
  }

  void _markBridges() {
    final adjacent = <_Node, List<_Edge>>{};
    for (final e in edges) {
      adjacent.putIfAbsent(e.a.root, () => []).add(e);
      adjacent.putIfAbsent(e.b.root, () => []).add(e);
    }
    final discovery = <_Node, int>{}, low = <_Node, int>{};
    var clock = 0;
    void visit(_Node v, _Edge? parent) {
      discovery[v] = low[v] = clock++;
      for (final e in adjacent[v]!) {
        if (identical(e, parent)) continue;
        final w = e.a.root == v ? e.b.root : e.a.root;
        if (!discovery.containsKey(w)) {
          visit(w, e);
          low[v] = math.min(low[v]!, low[w]!);
          if (low[w]! > discovery[v]!) e.bridge = true;
        } else {
          low[v] = math.min(low[v]!, discovery[w]!);
        }
      }
    }

    for (final v in adjacent.keys) {
      if (!discovery.containsKey(v)) visit(v, null);
    }
    final bridges = edges.where((e) => e.bridge).toList();
    if (bridges.isNotEmpty) {
      _diagnose(
        'openBoundary',
        'Open or dangling portions contribute no bounded material and are never closed.',
        bridges.map((e) => e.curve),
      );
    }
  }

  int _compare(_Half a, _Half b) {
    final ta = a.tangent, tb = b.tangent;
    if (_cross(ta, tb).abs() <= _roundoff && ta.dot(tb) > 0) {
      final curveOrder = a.curvature.compareTo(b.curvature);
      if (curveOrder != 0) return curveOrder;
      // Equal tangents and curvatures should have been deduplicated.
      return a.edge.index.compareTo(b.edge.index);
    }
    return _angle(ta).compareTo(_angle(tb));
  }

  BoundaryPortion _portion(_Half h) {
    final c = h.edge.curve;
    final sources =
        h.edge.sources.map((s) => h.forward ? s : s.reversed()).toList()
          ..sort((a, b) => a.inputId.compareTo(b.inputId));
    if (c.input case final PlanarCircle circle) {
      return BoundaryPortion.arc(
        center: circle.center,
        radius: circle.radius,
        startAngle: h.t0,
        sweepAngle: h.t1 - h.t0,
        sources: sources,
      );
    }
    final line = c.input as PlanarSegment;
    Vector2 at(double t) => t == 0
        ? line.start
        : t == 1
        ? line.end
        : line.start + (line.end - line.start) * t;
    return BoundaryPortion.line(
      start: at(h.t0),
      end: at(h.t1),
      sources: sources,
    );
  }

  List<_Cycle> _walk(List<_Half> boundary) {
    final outgoing = <_Node, List<_Half>>{};
    for (final h in boundary) {
      outgoing.putIfAbsent(h.start, () => []).add(h);
    }
    for (final list in outgoing.values) {
      list.sort(_compare);
    }
    final next = <_Half, _Half>{};
    final boundarySet = boundary.toSet();
    for (final h in boundary) {
      final choices = outgoing[h.end]!;
      if (boundarySet.contains(h.twin)) {
        final at = choices.indexOf(h.twin);
        next[h] = choices[(at + choices.length - 1) % choices.length];
      } else {
        // Union boundaries have exactly one outgoing edge at each manifold vertex.
        next[h] = choices.single;
      }
    }
    final visited = <_Half>{}, cycles = <_Cycle>[];
    for (final first in boundary) {
      if (visited.contains(first)) continue;
      final walk = <_Half>[];
      var h = first;
      while (!visited.contains(h)) {
        visited.add(h);
        walk.add(h);
        h = next[h]!;
      }
      if (h != first) {
        _diagnose(
          'numericAmbiguity',
          'Boundary walk did not return to its start.',
          walk.map((e) => e.edge.curve),
          error: true,
        );
        continue;
      }
      // Tangent contacts can make an orbit visit a vertex more than once.
      // Decompose that orbit into simple analytic loops before nesting.
      final pending = <_Half>[];
      for (final edge in walk) {
        pending.add(edge);
        final at = pending.indexWhere((e) => e.start == edge.end);
        if (at >= 0) {
          final loop = pending.sublist(at);
          pending.removeRange(at, pending.length);
          final value = RegionLoop(loop.map(_portion));
          if (value.signedArea == 0 || !value.signedArea.isFinite) {
            _diagnose(
              'numericRange',
              'Boundary area cannot be resolved in model units.',
              loop.map((e) => e.edge.curve),
              error: true,
            );
          } else {
            cycles.add(_Cycle(loop, value));
          }
        }
      }
    }
    return cycles;
  }

  List<_Cycle> _classify(List<_Cycle> cycles) {
    final positive = cycles.where((c) => c.loop.signedArea > 0).toList();
    for (final hole in cycles.where((c) => c.loop.signedArea < 0)) {
      final edgeIds = hole.halves.map((h) => h.edge.index).toSet();
      final sample = hole.loop.portions.first.pointAt(0.5);
      final containers =
          positive
              .where(
                (c) =>
                    !c.halves.any((h) => edgeIds.contains(h.edge.index)) &&
                    c.loop.containsInterior(sample),
              )
              .toList()
            ..sort((a, b) => a.loop.signedArea.compareTo(b.loop.signedArea));
      if (containers.isNotEmpty) containers.first.holes.add(hole);
    }
    String key(_Cycle c) {
      final portions =
          c.loop.portions
              .map(
                (p) => jsonEncode(
                  p.sources
                      .map((s) => [s.inputId, s.startParameter, s.endParameter])
                      .toList(),
                ),
              )
              .toList()
            ..sort();
      return jsonEncode(portions);
    }

    positive.sort((a, b) => key(a).compareTo(key(b)));
    for (final c in positive) {
      c.holes.sort((a, b) => key(a).compareTo(key(b)));
    }
    return positive;
  }

  RegionSelection _union(Set<String> selected) {
    final boundary = <int, _Half>{};
    for (final c in cells.where((c) => selected.contains(c.region!.id))) {
      for (final h in [c, ...c.holes].expand((l) => l.halves)) {
        if (boundary.containsKey(h.edge.index)) {
          boundary.remove(h.edge.index);
        } else {
          boundary[h.edge.index] = h;
        }
      }
    }
    final degree = <_Node, int>{};
    for (final h in boundary.values) {
      degree.update(h.start, (n) => n + 1, ifAbsent: () => 1);
      degree.update(h.end, (n) => n + 1, ifAbsent: () => 1);
    }
    if (degree.values.any((n) => n != 2)) {
      return RegionSelection([], [
        RegionDiagnostic(
          'nonManifoldSelection',
          'Selected material has a point-only connection or touching hole; extrusion would be non-manifold.',
          boundary.values
              .expand((h) => h.edge.sources.map((s) => s.inputId))
              .toSet()
              .toList()
            ..sort(),
          isError: true,
        ),
      ]);
    }
    final before = diagnostics.length;
    final components = _classify(_walk(boundary.values.toList()));
    final selectionDiagnostics = diagnostics.sublist(before);
    diagnostics.removeRange(before, diagnostics.length);
    if (selectionDiagnostics.any((d) => d.isError)) {
      return RegionSelection([], selectionDiagnostics);
    }
    return RegionSelection(
      components.indexed.map(
        (entry) => PlanarRegion(
          id: 'union:${entry.$1}',
          outer: entry.$2.loop,
          holes: entry.$2.holes.map((h) => h.loop),
        ),
      ),
      [],
    );
  }
}
