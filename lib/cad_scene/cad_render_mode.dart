/// How CAD geometry is displayed by a scene.
enum CadRenderMode {
  /// Opaque, lit faces and visible boundary edges.
  shaded,

  /// All boundary edges, including geometry behind other objects.
  frame,
}
