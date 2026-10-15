import 'package:flutter/foundation.dart';

/// The renderer owns the complete CAD scene, including inactive sketches.
enum CadRenderBackend {
  canvas,
  metal;

  static CadRenderBackend get configured {
    const backend = String.fromEnvironment('CAD_RENDER_BACKEND');
    if (backend == 'metal') return metal;
    if (backend == 'canvas') return canvas;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
        ? metal
        : canvas;
  }
}
