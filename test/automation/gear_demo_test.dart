import 'dart:math' as math;

import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:faust_cad_app_2/automation/automation_renderer.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/mcp_demo_geometry.dart';
import '../support/extrusion_validation.dart';
import 'automation_controller_test.dart' show emptyDocument, data;

void main() {
  test(
    'gear workflow produces two closed, holed bodies in four undo steps',
    () async {
      final document = emptyDocument();
      final ai = AutomationController(document);
      final session = data(await ai.call('demo', 'cad_begin', {}))['sessionId'];
      var serial = 0;
      try {
        for (final (id, center, phase) in [
          ('a', 0.0, 0.0),
          ('b', 30.0, math.pi / 24),
        ]) {
          Future<Map<String, Object?>> edit(
            String name,
            Map<String, Object?> args,
          ) => ai.call('demo', name, {
            'sessionId': session,
            'requestId': '${++serial}',
            'expectedRevision': document.evaluation.revision,
            ...args,
          });
          final sketch = await edit(
            'cad_set_sketch',
            demoGearSketch(id, center, phase),
          );
          expect(sketch['isError'], isNull, reason: sketch.toString());
          final regions = data(
            await ai.call('demo', 'cad_get_profiles', {'sketchId': id}),
          );
          final material = (regions['regions'] as List).cast<Map>().singleWhere(
            (r) => r['holeCount'] == 1,
          );
          final extruded = await edit('cad_extrude', {
            'featureId': '$id-body',
            'sketchId': id,
            'regionIds': [material['id']],
            'distance': 5,
          });
          expect(extruded['isError'], isNull, reason: extruded.toString());
          final body = document.evaluation.geometry.last as Solid;
          expect(body.shells.single.isClosed, isTrue);
          final vertices = [
            for (final face in body.shells.single.faces)
              for (final edge in face.outerWire.edges) edge.begin.vector,
          ];
          expect(vertices.map((v) => v.z).reduce(math.min), 0);
          expect(vertices.map((v) => v.z).reduce(math.max), 5);
          expect(
            analyticBoundaryVolume(body, PlanarFrame.xy()),
            closeTo((material['area'] as num) * 5, 1e-6),
          );
          final bores = body.shells.single.faces
              .map((f) => f.surface)
              .whereType<CylinderSurface>();
          expect(bores, isNotEmpty);
          expect(
            bores.every(
              (s) =>
                  (s.radius - 2.5).abs() < 1e-10 &&
                  (s.origin.x - center).abs() < 1e-10 &&
                  s.origin.y.abs() < 1e-10,
            ),
            isTrue,
          );
        }
        expect(document.undoCount, 4);
        expect(document.evaluation.geometry, hasLength(2));
        final revision = document.evaluation.revision;
        TestWidgetsFlutterBinding.ensureInitialized();
        final renderer = AutomationRenderer(document);
        final rendered = await renderer.render({
          'target': [15, 0, 2.5],
          'width': 320,
          'height': 240,
        });
        expect(
          (rendered['content'] as List).cast<Map>().where(
            (c) => c['type'] == 'image',
          ),
          hasLength(1),
        );
        expect(document.evaluation.revision, revision);
        expect(document.undoCount, 4);
      } finally {
        ai.dispose();
        document.dispose();
      }
    },
  );
}
