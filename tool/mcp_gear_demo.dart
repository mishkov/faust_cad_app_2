import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'mcp_demo_geometry.dart';

/// Exercises the real stdio MCP adapter against a running desktop app.
Future<void> main(List<String> arguments) async {
  final process = await Process.start('dart', ['run', 'bin/faust_mcp.dart']);
  final errors = process.stderr.listen(stderr.add);
  final lines = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  var serial = 0;
  Future<Map<String, Object?>> rpc(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = ++serial;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    if (!await lines.moveNext().timeout(const Duration(seconds: 90))) {
      throw StateError('MCP process closed');
    }
    final response = jsonDecode(lines.current) as Map<String, Object?>;
    if (response['error'] != null) throw StateError('${response['error']}');
    return response['result'] as Map<String, Object?>;
  }

  Future<Map<String, Object?>> tool(
    String name, [
    Map<String, Object?> args = const {},
  ]) async {
    final result = await rpc('tools/call', {'name': name, 'arguments': args});
    if (result['isError'] == true) throw StateError('${result['content']}');
    return result;
  }

  Map<String, Object?> data(Map<String, Object?> result) =>
      result['structuredContent'] as Map<String, Object?>;
  String? session;
  try {
    await rpc('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': {},
      'clientInfo': {'name': 'faust-gear-demo', 'version': '1.0'},
    });
    process.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
    );
    await rpc('tools/list', {});
    var revision = data(await tool('cad_get_document'))['revision'] as int;
    final started = data(await tool('cad_begin'));
    session = started['sessionId'] as String;
    revision = started['revision'] as int;
    var operation = 0;
    Future<void> edit(String name, Map<String, Object?> args) async {
      final result = data(
        await tool(name, {
          'sessionId': session,
          'requestId': 'gear-demo-${++operation}',
          'expectedRevision': revision,
          ...args,
        }),
      );
      revision = result['revision'] as int;
    }

    if (arguments.contains('--replace-demo-cubes')) {
      final features = data(await tool('cad_get_document'))['features'] as List;
      for (final f in features.cast<Map>()) {
        if (f['type'] == 'cube' &&
            (f['id'] == 'cube-a' || f['id'] == 'cube-b')) {
          await edit('cad_delete_feature', {'featureId': f['id']});
        }
      }
    }
    for (final (id, x, phase) in [
      ('gear-a', 0.0, 0.0),
      ('gear-b', 30.0, math.pi / 24),
    ]) {
      await edit('cad_set_sketch', demoGearSketch(id, x, phase));
      final profiles = data(await tool('cad_get_profiles', {'sketchId': id}));
      revision = profiles['revision'] as int;
      final region = (profiles['regions'] as List).cast<Map>().singleWhere(
        (r) => r['holeCount'] == 1,
      );
      await edit('cad_extrude', {
        'featureId': '$id-body',
        'name': '$id • 5 mm',
        'sketchId': id,
        'regionIds': [region['id']],
        'distance': 5,
      });
    }
    final view = await tool('cad_render', {
      'target': [15, 0, 2.5],
      'distance': 80,
      'yaw': 0,
      'pitch': -65,
      'width': 1000,
      'height': 700,
    });
    final image = (view['content'] as List).cast<Map>().singleWhere(
      (c) => c['type'] == 'image',
    );
    await Directory('build').create(recursive: true);
    await File('build/mcp_gears.png')
        .writeAsBytes(base64Decode(image['data'] as String));
    stdout.writeln(
      'Created 2 demonstration gears: centers 30 mm apart, bores Ø5 mm, thickness 5 mm.',
    );
    stdout.writeln('Inspection image: build/mcp_gears.png');
  } finally {
    if (session != null) {
      try {
        await tool('cad_finish', {'sessionId': session});
      } catch (_) {
        /* Disconnect also revokes the session. */
      }
    }
    await process.stdin.close();
    await lines.cancel();
    await process.exitCode;
    await errors.cancel();
  }
}
