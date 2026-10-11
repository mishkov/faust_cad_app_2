import 'dart:convert';

import 'boundary_portion.dart';
import 'boundary_span.dart';
import 'planar_region.dart';
import 'region_loop.dart';

/// Canonical directed boundary correspondence independent of analytic seams.
final class ProfileLineage {
  /// Groups adjacent patches across synthetic seams, retaining authored events.
  ///
  /// Returns `null` if any portion lacks supported junction correspondence.
  static List<BoundarySpan>? spans(RegionLoop loop) {
    try {
      return _spans(loop);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static List<BoundarySpan>? _spans(RegionLoop loop) {
    final portions = loop.portions;
    if (portions.isEmpty ||
        portions.any(
          (p) =>
              p.lineage == null ||
              p.sources.isEmpty ||
              p.sources.any(
                (s) =>
                    s.inputId.isEmpty ||
                    !s.startParameter.isFinite ||
                    !s.endParameter.isFinite ||
                    s.startParameter == s.endParameter,
              ),
        )) {
      return null;
    }
    String sources(BoundaryPortion p) => jsonEncode([
      p.isArc ? 'circle' : 'segment',
      p.sources
          .map((s) => [s.inputId, s.endParameter > s.startParameter ? 1 : -1])
          .toList()
        ..sort((a, b) => (a[0] as String).compareTo(b[0] as String)),
    ]);
    for (var i = 0; i < portions.length; i++) {
      final p = portions[i], next = portions[(i + 1) % portions.length];
      if (p.lineage!.end != next.lineage!.start ||
          p.lineage!.end == null && sources(p) != sources(next)) {
        return null;
      }
    }
    final first = portions.indexWhere((p) => p.lineage!.start != null);
    final ordered = first < 0
        ? portions
        : [...portions.skip(first), ...portions.take(first)];
    final result = <BoundarySpan>[];
    var patches = <BoundaryPortion>[];
    Object? junction(String? signature) => signature == null
        ? null
        : (jsonDecode(signature) as List)
              .map((e) => jsonDecode(e as String))
              .toList();
    void finish() {
      final p = patches.first;
      result.add(
        BoundarySpan(
          jsonEncode([
            ...jsonDecode(sources(p)) as List,
            junction(p.lineage!.start),
            junction(patches.last.lineage!.end),
          ]),
          patches,
        ),
      );
      patches = [];
    }

    for (final p in ordered) {
      patches.add(p);
      if (p.lineage!.end != null) finish();
    }
    if (patches.isNotEmpty) finish();
    return List.unmodifiable(result);
  }

  /// Encodes outer and hole loops in cyclic, input-order-independent form.
  static String? signature(PlanarRegion region) {
    String? loop(RegionLoop value) {
      final boundaries = spans(value);
      if (boundaries == null) return null;
      final keys = boundaries.map((s) => s.key).toList();
      return _cycle(keys);
    }

    final outer = loop(region.outer);
    final holes = region.holes.map(loop).toList();
    if (outer == null || holes.any((h) => h == null)) return null;
    final sorted = holes.cast<String>()..sort();
    try {
      return canonicalSignature([
        jsonDecode(outer),
        sorted.map(jsonDecode).toList(),
      ]);
    } on FormatException {
      return null;
    }
  }

  static String _cycle(List<String> keys) {
    final rotations = [
      for (var i = 0; i < keys.length; i++)
        jsonEncode([...keys.skip(i), ...keys.take(i)].map(jsonDecode).toList()),
    ]..sort();
    return rotations.first;
  }

  /// Validates and canonicalizes a stored lineage signature without geometry.
  static String canonicalSignature(Object? value) {
    Never invalid() =>
        throw const FormatException('Unsupported profile lineage');
    Object? junction(Object? value) {
      if (value == null) return null;
      final events = value;
      if (events is! List || events.isEmpty) invalid();
      for (final event in events) {
        final fields = event;
        if (fields is! List) invalid();
        final endpoint =
            fields.length == 3 &&
            fields[0] == 'endpoint' &&
            fields[1] is String &&
            (fields[1] as String).isNotEmpty &&
            (fields[2] == 'start' || fields[2] == 'end');
        final intersection =
            fields.length == 4 &&
            fields[0] == 'intersection' &&
            fields[1] is String &&
            fields[2] is String &&
            (fields[1] as String).isNotEmpty &&
            (fields[1] as String).compareTo(fields[2] as String) < 0 &&
            fields[3] is int &&
            [-1, 0, 1].contains(fields[3]);
        if (!endpoint && !intersection) invalid();
      }
      final canonical = events.map(jsonEncode).toSet().toList()..sort();
      return canonical.map(jsonDecode).toList();
    }

    String loop(Object? value) {
      final edges = value;
      if (edges is! List || edges.isEmpty) invalid();
      final keys = <String>[];
      for (final edge in edges) {
        final fields = edge;
        if (fields is! List ||
            fields.length != 4 ||
            !['circle', 'segment'].contains(fields[0]) ||
            fields[1] is! List) {
          invalid();
        }
        final sources = List<Object?>.of(fields[1] as List);
        if (sources.isEmpty) invalid();
        final ids = <String>{};
        for (final source in sources) {
          if (source is! List ||
              source.length != 2 ||
              source[0] is! String ||
              (source[0] as String).isEmpty ||
              !ids.add(source[0] as String) ||
              source[1] is! int ||
              ![-1, 1].contains(source[1])) {
            invalid();
          }
        }
        sources.sort(
          (a, b) =>
              ((a as List)[0] as String).compareTo((b as List)[0] as String),
        );
        final start = junction(fields[2]), end = junction(fields[3]);
        if ((start == null || end == null) &&
            !(start == null &&
                end == null &&
                fields[0] == 'circle' &&
                edges.length == 1)) {
          invalid();
        }
        keys.add(jsonEncode([fields[0], sources, start, end]));
      }
      for (var i = 0; i < keys.length; i++) {
        if (jsonEncode((jsonDecode(keys[i]) as List)[3]) !=
            jsonEncode((jsonDecode(keys[(i + 1) % keys.length]) as List)[2])) {
          invalid();
        }
      }
      return _cycle(keys);
    }

    if (value is! List || value.length != 2 || value[1] is! List) invalid();
    final holes = (value[1] as List).map(loop).toList()..sort();
    return jsonEncode([
      jsonDecode(loop(value[0])),
      holes.map(jsonDecode).toList(),
    ]);
  }
}
