import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'automation_controller.dart';

/// Authenticates a local bridge connection to the running app.
final class AutomationServer {
  AutomationServer(this.controller);
  final AutomationController controller;
  HttpServer? _server;
  final _sockets = <WebSocket>{};
  String? endpoint;
  bool _closed = false;

  Future<String> start({String? token, int port = 47831}) async {
    if (_closed) throw StateError('Server is closed');
    if (endpoint != null) return endpoint!;
    final secret =
        token ??
        List.generate(
          32,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    if (secret.length < 16 || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(secret)) {
      throw ArgumentError(
        'MCP token must contain at least 16 letters, numbers, underscores or hyphens.',
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Server is closed');
    }
    _server = server;
    endpoint = 'ws://127.0.0.1:${server.port}/$secret';
    server.listen((request) async {
      if (request.headers.value('origin') != null ||
          request.uri.path != '/$secret' ||
          request.uri.hasQuery ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      WebSocket socket;
      try {
        socket = await WebSocketTransformer.upgrade(request);
      } catch (_) {
        return;
      }
      socket.pingInterval = const Duration(seconds: 5);
      _sockets.add(socket);
      final connection =
          '${socket.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
      var connected = true;
      var queued = Future<void>.value();
      void disconnected() {
        connected = false;
        _sockets.remove(socket);
        controller.disconnect(connection);
      }

      socket.listen(
        (message) {
          queued = queued.then((_) async {
            if (!connected) return;
            if (message is! String || message.length > 512 * 1024) {
              await socket.close(WebSocketStatus.messageTooBig);
              return;
            }
            Object? id;
            Map<String, Object?> result;
            try {
              final payload = jsonDecode(message) as Map<String, Object?>;
              id = payload['id'];
              if (id is! int && id is! String) {
                throw const FormatException('Invalid request ID');
              }
              result = await controller.call(
                connection,
                payload['name'] as String,
                (payload['arguments'] as Map<String, Object?>?) ?? {},
              );
            } catch (error) {
              result = {
                'isError': true,
                'content': [
                  {'type': 'text', 'text': error.toString()},
                ],
              };
            }
            if (socket.readyState == WebSocket.open) {
              socket.add(jsonEncode({'id': id, 'result': result}));
            }
          });
        },
        onDone: disconnected,
        onError: (_) => disconnected(),
      );
    });
    return endpoint!;
  }

  Future<void> close() async {
    _closed = true;
    controller.stop(pause: false);
    for (final socket in _sockets.toList()) {
      await socket.close(WebSocketStatus.goingAway);
    }
    await _server?.close(force: true);
    _server = null;
    endpoint = null;
  }
}
