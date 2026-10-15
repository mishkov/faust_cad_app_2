/// Optional per-paint layer counters and CPU samples for desktop profiling.
class ViewportLayerCounts {
  int planarFaces = 0;
  int curvedTriangles = 0;
  int edges = 0;
  int sketchOverlays = 0;
  int hiddenEdges = 0;
  int hiddenTriangles = 0;
  int meshBatches = 0;
  int meshVertices = 0;
  int meshDraws = 0;
  int planarDraws = 0;
  int edgeDraws = 0;
  int maskDraws = 0;
  int resolvedTriangles = 0;
  int visibilityFallbacks = 0;
  int visibilityWork = 0;
  int projectionMicroseconds = 0;
  int facesMicroseconds = 0;
  int edgesMicroseconds = 0;
  int sketchMicroseconds = 0;

  Map<String, int> toJson() => {
    'planar_faces': planarFaces,
    'curved_triangles': curvedTriangles,
    'edges': edges,
    'sketch_overlays': sketchOverlays,
    'hidden_edges': hiddenEdges,
    'hidden_triangles': hiddenTriangles,
    'mesh_batches': meshBatches,
    'mesh_vertices': meshVertices,
    'mesh_draws': meshDraws,
    'cad_draws': meshDraws + planarDraws + edgeDraws + maskDraws,
    'planar_draws': planarDraws,
    'edge_draws': edgeDraws,
    'mask_draws': maskDraws,
    'resolved_triangles': resolvedTriangles,
    'visibility_fallbacks': visibilityFallbacks,
    'visibility_work': visibilityWork,
    'ui_projection_us': projectionMicroseconds,
    'ui_faces_us': facesMicroseconds,
    'ui_edges_us': edgesMicroseconds,
    'ui_sketch_us': sketchMicroseconds,
  };
}
