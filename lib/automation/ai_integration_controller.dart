import 'dart:async';

import 'package:flutter/foundation.dart';

import 'automation_controller.dart';
import 'automation_server.dart';

/// Manages the local MCP connection independently of the settings dialog.
final class AiIntegrationController extends ChangeNotifier {
  AiIntegrationController(this.automation, {this._port = 47831}) {
    automation.addListener(_changed);
  }

  final AutomationController automation;
  AutomationServer? _server;
  int _port;
  bool _busy = false;
  bool _disposed = false;
  String? _error;

  int get port => _port;
  String? get endpoint => _server?.endpoint;
  String? get error => _error;
  bool get isEnabled => endpoint != null;
  bool get isBusy => _busy;

  void setPort(int port) {
    if (_busy || isEnabled) {
      throw StateError('Disable MCP before changing its port.');
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError('Port must be between 0 and 65535.');
    }
    _port = port;
    _error = null;
    _changed();
  }

  Future<void> enable({String? token}) async {
    if (_busy || _disposed) return;
    if (isEnabled) {
      automation.enable();
      return;
    }
    _busy = true;
    _error = null;
    final server = AutomationServer(automation);
    _server = server;
    _changed();
    try {
      await server.start(port: _port, token: token);
      if (!_disposed) automation.enable();
    } catch (error) {
      await server.close();
      _server = null;
      _error = error is UnsupportedError
          ? 'MCP is available in the desktop app.'
          : 'Unable to enable MCP. Check the port and try again.';
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> disable() async {
    if (_busy || _disposed) return;
    _busy = true;
    _error = null;
    final server = _server;
    _server = null;
    automation.stop(pause: false);
    _changed();
    try {
      await server?.close();
    } finally {
      _busy = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    automation.removeListener(_changed);
    final server = _server;
    _server = null;
    if (server != null) unawaited(server.close());
    super.dispose();
  }
}
