import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/rendering/projected_face.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/projected_mesh_batch.dart';
import 'package:faust_cad_app_2/cad_scene/rendering/viewport_layer_counts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ProjectedFace triangle(Color color) {
    const points = [Offset(2, 2), Offset(14, 2), Offset(2, 14)];
    return ProjectedFace(
      Path()..addPolygon(points, true),
      Vector3(0, 0, 1),
      Colors.white,
      contours: [points],
      meshPoints: points,
      meshColors: [color, color, color],
    );
  }

  test(
    'native recordings own data after reuse and explicit vertices disposal',
    () async {
      final batch = ProjectedMeshBatch();
      ui.Picture record(Color color) {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        batch.clear();
        batch.addFace(canvas, triangle(color), null);
        batch.flush(canvas, null);
        return recorder.endRecording();
      }

      final first = record(const Color(0xffff0000));
      final second = record(const Color(0xff0000ff));
      for (final (picture, expected) in [
        (first, [255, 0, 0, 255]),
        (second, [0, 0, 255, 255]),
      ]) {
        final image = await picture.toImage(16, 16);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(bytes.sublist((4 * 16 + 4) * 4, (4 * 16 + 4) * 4 + 4), expected);
        image.dispose();
        picture.dispose();
      }
    },
  );
  test('submissions stay bounded without dropping triangles', () {
    final batch = ProjectedMeshBatch(), counts = ViewportLayerCounts();
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final face = triangle(Colors.white);
    for (var i = 0; i < 1500; i++) {
      batch.addFace(canvas, face, counts);
    }
    batch.flush(canvas, counts);
    recorder.endRecording().dispose();
    expect(counts.meshBatches, 2);
    expect(counts.meshDraws, 2);
    expect(counts.meshVertices, 4500);
  });
}
