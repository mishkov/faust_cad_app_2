import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Coalesces camera updates; at most one platform message waits for acknowledgement.
final class MetalViewportController {
  static const channel = MethodChannel('cad.metal');
  static final _active = <int, MetalViewportController>{};
  static bool _handlerInstalled = false;
  final error = ValueNotifier<String?>(null);
  int? _id;
  int _serial = 0;
  bool _disposed = false, _sending = false, _initializing = false;
  Map<String, Object>? _pending;
  final _ready = Completer<int>();

  Future<int> get ready => _ready.future;
  int? get rendererId => _id;

  Future<void> initialize() async {
    if (_initializing || _disposed) return;
    _initializing = true;
    try {
      if (!_handlerInstalled) {
        _handlerInstalled = true;
        channel.setMethodCallHandler((call) async {
          if (call.method == 'error') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            _active[args['id']]?.error.value = args['message'] as String;
          }
        });
      }
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
        throw UnsupportedError('The Metal viewport requires macOS.');
      }
      final id = (await channel.invokeMethod<int>('create'))!;
      _id = id;
      _ready.complete(id);
      if (_disposed) {
        await channel.invokeMethod<void>('dispose', {'id': id});
        return;
      }
      _active[id] = this;
      unawaited(_drain());
    } catch (e) {
      if (!_disposed) error.value = '$e';
      // A failed native backend is displayed explicitly; never replaced by Canvas.
      if (!_ready.isCompleted) _ready.complete(-1);
    }
  }

  void update(Map<String, Object> frame) {
    if (_disposed) return;
    // Keep geometry revisions even if a camera-only update supersedes this packet.
    _pending = {...?_pending, ...frame, 'serial': ++_serial};
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_sending || _id == null || _disposed) return;
    _sending = true;
    try {
      while (_pending != null && !_disposed) {
        final frame = _pending!;
        _pending = null;
        await channel.invokeMethod<void>('update', {'id': _id, ...frame});
      }
    } catch (e) {
      if (!_disposed) error.value = '$e';
    } finally {
      _sending = false;
    }
  }

  /// Live counters are queried outside rendering so diagnostics do not drive frames.
  Future<Map<String, dynamic>> stats() async => Map<String, dynamic>.from(
    (await channel.invokeMapMethod<String, dynamic>('stats', {
      'id': await ready,
    }))!,
  );

  /// Starts an independent performance capture without changing frame IDs.
  Future<double> resetMetrics() async => (await channel.invokeMethod<double>(
    'resetMetrics',
    {'id': await ready},
  ))!;

  /// Offscreen BGRA readback for validation/export only, never for presentation.
  Future<Map<String, dynamic>> capture() async {
    if (await ready < 0 || _disposed) {
      throw StateError('Metal renderer unavailable');
    }
    while (_sending || _pending != null) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return Map<String, dynamic>.from(
      (await channel.invokeMapMethod<String, dynamic>('capture', {
        'id': await ready,
      }))!,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    final id = _id;
    if (id != null) {
      _active.remove(id);
      unawaited(channel.invokeMethod<void>('dispose', {'id': id}));
    }
    error.dispose();
  }
}
