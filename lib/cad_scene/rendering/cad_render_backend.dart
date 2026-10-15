enum CadRenderBackend {
  canvas,
  flutterGpu;

  static const developmentDefault =
      String.fromEnvironment('CAD_RENDER_BACKEND') == 'flutter-gpu'
      ? flutterGpu
      : canvas;
}
