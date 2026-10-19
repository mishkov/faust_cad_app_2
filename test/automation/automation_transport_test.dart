import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:faust_cad_app_2/automation/automation_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'automation_controller_test.dart' show emptyDocument, data;

void main() {
  test(
    'real stdio MCP negotiation, tool calls, and shutdown release the app lock',
    () async {
      final document = emptyDocument();
      final ai = AutomationController(document);
      final server = AutomationServer(ai);
      final endpoint = await server.start(port: 0);
      final process = await Process.start(
        'dart',
        ['run', 'bin/faust_mcp.dart'],
        environment: {'FAUST_CAD_ENDPOINT': endpoint},
      );
      final stderr = StringBuffer();
      final errors = process.stderr
          .transform(utf8.decoder)
          .listen(stderr.write);
      final lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      var id = 0;
      Future<Map<String, Object?>> rpc(
        String method, [
        Map<String, Object?> params = const {},
      ]) async {
        process.stdin.writeln(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': ++id,
            'method': method,
            'params': params,
          }),
        );
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 30)),
          isTrue,
          reason: stderr.toString(),
        );
        final result = jsonDecode(lines.current) as Map<String, Object?>;
        expect(result['id'], id);
        return result;
      }

      try {
        expect((await rpc('tools/list'))['error'], isNotNull);
        final initialized = await rpc('initialize', {
          'protocolVersion': '2025-11-25',
          'capabilities': {},
          'clientInfo': {'name': 'test', 'version': '1'},
        });
        expect((initialized['result'] as Map)['protocolVersion'], '2025-11-25');
        process.stdin.writeln(
          jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        );
        final listed = await rpc('tools/list');
        expect(
          ((listed['result'] as Map)['tools'] as List).length,
          greaterThan(8),
        );
        final began = await rpc('tools/call', {
          'name': 'cad_begin',
          'arguments': {},
        });
        expect(
          data(began['result'] as Map<String, Object?>)['sessionId'],
          isA<String>(),
        );
        expect(document.isEditLocked, isTrue);
        final rejected = await rpc('tools/call', {
          'name': 'cad_set_sketch',
          'arguments': {},
        });
        expect((rejected['result'] as Map)['isError'], isTrue);
        await process.stdin.close();
        expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(document.isEditLocked, isFalse);
      } finally {
        process.kill();
        await lines.cancel();
        await errors.cancel();
        await server.close();
        ai.dispose();
        document.dispose();
      }
    },
  );

  test('bridge rejects wrong tokens and browser origins', () async {
    final document = emptyDocument();
    final ai = AutomationController(document);
    final server = AutomationServer(ai);
    final endpoint = await server.start(port: 0);
    try {
      await expectLater(
        WebSocket.connect(
          Uri.parse(endpoint).replace(path: '/wrong').toString(),
        ),
        throwsA(isA<WebSocketException>()),
      );
      await expectLater(
        WebSocket.connect(endpoint, headers: {'Origin': 'https://example.com'}),
        throwsA(isA<WebSocketException>()),
      );
      expect(ai.isActive, isFalse);
    } finally {
      await server.close();
      ai.dispose();
      document.dispose();
    }
  });
}
