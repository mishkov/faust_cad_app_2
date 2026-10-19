import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:faust_cad_app_2/automation/automation_tools.dart';

/// Runs the stdio MCP adapter; only protocol messages are written to stdout.
Future<void> main(List<String> arguments) async {
  final rawEndpoint = Platform.environment['FAUST_CAD_ENDPOINT'];
  final endpoint = rawEndpoint == null ? null : Uri.tryParse(rawEndpoint);
  if (endpoint == null ||
      endpoint.scheme != 'ws' ||
      endpoint.host != '127.0.0.1' ||
      endpoint.path.length < 17) {
    stderr.writeln(
      'Set FAUST_CAD_ENDPOINT to the connection copied from Faust CAD.',
    );
    exitCode = 64;
    return;
  }
  WebSocket? socket;
  var serial = 0;
  var initialized = false;
  var ready = false;
  var inputClosed = false;
  final input = stdin.asBroadcastStream();
  final inputMonitor = input.listen(
    (_) {},
    onDone: () {
      inputClosed = true;
      unawaited(socket?.close());
    },
  );
  final pending = <int, Completer<Map<String, Object?>>>{};
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> args,
  ) async {
    if (inputClosed) throw StateError('MCP client disconnected.');
    if (socket == null) {
      final connected = await WebSocket.connect(endpoint.toString())
          .timeout(const Duration(seconds: 5));
      if (inputClosed) {
        await connected.close();
        throw StateError('MCP client disconnected.');
      }
      socket = connected;
      connected.pingInterval = const Duration(seconds: 5);
      void disconnected() {
        socket = null;
        for (final p in pending.values) {
          if (!p.isCompleted) {
            p.completeError(
              StateError('App disconnected; inspect before retrying.'),
            );
          }
        }
        pending.clear();
      }

      connected.listen(
        (message) {
          try {
            final payload =
                jsonDecode(message as String) as Map<String, Object?>;
            pending
                .remove(payload['id'])
                ?.complete(payload['result'] as Map<String, Object?>);
          } catch (_) {
            disconnected();
          }
        },
        onDone: disconnected,
        onError: (_) => disconnected(),
      );
    }
    final id = ++serial;
    final completer = Completer<Map<String, Object?>>();
    pending[id] = completer;
    socket!.add(jsonEncode({'id': id, 'name': name, 'arguments': args}));
    try {
      return await completer.future.timeout(const Duration(seconds: 90));
    } finally {
      pending.remove(id);
    }
  }

  try {
    await for (final line
        in input.transform(utf8.decoder).transform(const LineSplitter())) {
      Object? id;
      Map<String, Object?> response;
      try {
        final request = jsonDecode(line);
        if (request is! Map<String, Object?> ||
            request['jsonrpc'] != '2.0' ||
            request['method'] is! String) {
          throw const FormatException('Invalid JSON-RPC request');
        }
        id = request['id'];
        final method = request['method'] as String;
        if (id == null) {
          if (method == 'notifications/initialized' && initialized) {
            ready = true;
          }
          continue;
        }
        if (id is! int && id is! String) {
          throw const FormatException('Invalid request ID');
        }
        if (method == 'initialize') {
          initialized = true;
          ready = false;
          response = {
            'result': {
              'protocolVersion': '2025-11-25',
              'capabilities': {
                'tools': {'listChanged': false},
              },
              'serverInfo': {'name': 'faust-cad-2', 'version': '0.1.0'},
              'instructions': automationInstructions,
            },
          };
        } else if (method == 'ping') {
          response = {'result': <String, Object?>{}};
        } else if (!ready) {
          response = {
            'error': {
              'code': -32600,
              'message': 'Initialize the MCP connection first.',
            },
          };
        } else if (method == 'tools/list') {
          response = {
            'result': {'tools': automationTools},
          };
        } else if (method == 'tools/call') {
          try {
            final params = request['params'] as Map<String, Object?>;
            final name = params['name'] as String;
            final args = (params['arguments'] as Map<String, Object?>?) ?? {};
            validateAutomationArguments(name, args);
            response = {'result': await call(name, args)};
          } catch (error) {
            response = {
              'result': {
                'isError': true,
                'content': [
                  {'type': 'text', 'text': error.toString()},
                ],
              },
            };
          }
        } else {
          response = {
            'error': {'code': -32601, 'message': 'Method not found: $method'},
          };
        }
      } catch (error) {
        response = {
          'error': {
            'code': error is FormatException ? -32700 : -32600,
            'message': error.toString(),
          },
        };
      }
      stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, ...response}));
    }
  } finally {
    await inputMonitor.cancel();
    await socket?.close();
  }
}
