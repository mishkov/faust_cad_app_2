/// Optional per-paint layer counters and CPU samples for desktop profiling.
class ViewportLayerCounts {
  int planarFaces = 0;
  int curvedTriangles = 0;
  int edges = 0;
  int sketchOverlays = 0;
  int hiddenEdges = 0;
  int hiddenTriangles = 0;
  int meshBatches = 0;
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
    'ui_projection_us': projectionMicroseconds,
    'ui_faces_us': facesMicroseconds,
    'ui_edges_us': edgesMicroseconds,
    'ui_sketch_us': sketchMicroseconds,
  };
}
