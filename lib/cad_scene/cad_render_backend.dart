/// The renderer owns the complete CAD scene, including inactive sketches.
enum CadRenderBackend {
  canvas,
  metal;

  static const configured =
      String.fromEnvironment('CAD_RENDER_BACKEND') == 'metal' ? metal : canvas;
}
