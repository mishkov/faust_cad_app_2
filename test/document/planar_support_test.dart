import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2, Vector3;
import 'package:faust_cad_app_2/cad_scene/cad_objects/cylinder.dart';
import 'package:faust_cad_app_2/cad_scene/cad_surfaces/cylinder_surface.dart';
import 'package:faust_cad_app_2/cad_scene/geometry/planar_frame.dart';
import 'package:faust_cad_app_2/document/cad_document.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_evaluation_context.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/feature_output.dart';
import 'package:faust_cad_app_2/document/feature_result.dart';
import 'package:faust_cad_app_2/document/output_reference.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/document/planar_support_resolution.dart';

import '../support/attachment_fixtures.dart';

final producerId = FeatureId('producer');
final attachmentId = FeatureId('attachment');
OutputReference faceReference({FeatureId? id, String key = 'face'}) =>
    OutputReference(
      featureId: id ?? producerId,
      key: key,
      kind: OutputKind.face,
    );
FeatureDefinition producer({
  double angle = 0,
  double height = 0,
  String mode = 'planar',
  bool reversed = false,
}) => FeatureDefinition(
  id: producerId,
  type: 'producer',
  parameters: {
    'angle': angle,
    'height': height,
    'mode': mode,
    'reversed': reversed,
  },
);
FeatureDefinition attachment({FeatureId? id, OutputReference? reference}) =>
    FeatureDefinition(
      id: id ?? attachmentId,
      type: 'support',
      support: PlanarSupport.face(
        reference: reference ?? faceReference(),
        preferredDirection: Vector3(1, 0, 0),
      ),
    );

List<FeatureOutput> produce(FeatureDefinition d, FeatureEvaluationContext c) {
  final mode = d.parameters['mode'];
  if (mode == 'missing') return [];
  if (mode == 'failed') throw StateError('Producer failed');
  final planar = rectangle(
    tiltedFrame(
      (d.parameters['angle'] as num).toDouble(),
      height: (d.parameters['height'] as num).toDouble(),
    ),
    hole: true,
  );
  final face = mode == 'curved'
      ? Cylinder(frame: PlanarFrame.xy(), radius: 2, height: 5)
            .build()
            .single
            .shells
            .single
            .faces
            .firstWhere((f) => f.surface is CylinderSurface)
      : d.parameters['reversed'] == true
      ? planar.reversed()
      : planar;
  final output = FeatureOutput(
    key: 'face',
    kind: OutputKind.face,
    geometry: face,
  );
  return [output, if (mode == 'ambiguous') output];
}

void main() {
  var supportEvaluations = 0;
  final evaluators = <String, FeatureEvaluator>{
    'producer': produce,
    'support': (d, c) {
      supportEvaluations++;
      expect(c.support, isNotNull);
      return [];
    },
  };

  test('principal planes use Task 1 axis conventions', () {
    final doc = CadDocument(evaluators: evaluators);
    for (final plane in PrincipalPlane.values) {
      final resolution = PlanarSupportResolution.resolve(
        PlanarSupport.principal(plane),
        doc.evaluation,
      );
      expect(resolution.support!.boundary, isNull);
      final normal = resolution.support!.frame.normal;
      expect(normal, switch (plane) {
        PrincipalPlane.xy => Vector3(0, 0, 1),
        PrincipalPlane.xz => Vector3(0, -1, 0),
        PrincipalPlane.yz => Vector3(1, 0, 0),
      });
    }
  });

  test(
    'rotated face support follows producer edits with fixed projected axis',
    () {
      supportEvaluations = 0;
      final doc = CadDocument(
        evaluators: evaluators,
        features: [attachment(), producer(angle: 0.4, height: 3)],
      );
      expect(doc.features.first.dependencies, contains(producerId));
      expect(doc.evaluation.evaluationOrder, [producerId, attachmentId]);
      final before = doc.evaluation.features[attachmentId]!.support!;
      expect(
        before.frame.normal.distanceTo(
          Vector3(math.sin(0.4), 0, math.cos(0.4)),
        ),
        lessThan(1e-10),
      );
      expect(before.boundary!.innerWires, hasLength(1));
      // Infinite support permits local points outside the outer trim and in holes.
      expect(before.frame.localToWorld(Vector2(100, 100)).isNaN, isFalse);
      expect(before.frame.localToWorld(Vector2.zero()), Vector3(0, 0, 3));
      doc.setFeature(producer(angle: 1.2, height: 8));
      final after = doc.evaluation.features[attachmentId]!.support!;
      expect(after.frame.origin, Vector3(0, 0, 8));
      expect(after.frame.xAxis.dot(Vector3(1, 0, 0)), greaterThan(0));
      expect(
        after.frame.normal.distanceTo(Vector3(math.sin(1.2), 0, math.cos(1.2))),
        lessThan(1e-10),
      );
      expect(doc.evaluation.rebuiltFeatures, {producerId, attachmentId});
      expect(supportEvaluations, 2);
      expect(before.frame.origin, Vector3(0, 0, 3));
      final boundary = after.boundary!;
      boundary.outerWire.edges.first.begin.vector.z = 123;
      expect(after.boundary!.outerWire.edges.first.begin.vector.z, isNot(123));
      doc.setFeature(producer(angle: 1.21, height: 8));
      final nearby = doc.evaluation.features[attachmentId]!.support!;
      expect(nearby.frame.xAxis.dot(after.frame.xAxis), greaterThan(0.99));
      expect(nearby.frame.yAxis.dot(after.frame.yAxis), greaterThan(0.99));
    },
  );

  test('orientation reverses material normal while preferred local X stays deliberate', () {
    final doc = CadDocument(
      evaluators: evaluators,
      features: [producer(reversed: true), attachment()],
    );
    final frame = doc.evaluation.features[attachmentId]!.support!.frame;
    expect(frame.normal, Vector3(0, 0, -1));
    expect(frame.xAxis, Vector3(1, 0, 0));
    expect(frame.yAxis, Vector3(0, -1, 0));
  });

  test('missing, ambiguous, and curved references break attachment without fallback', () {
    final doc = CadDocument(
      evaluators: evaluators,
      features: [producer(), attachment()],
    );
    for (final mode in ['missing', 'ambiguous', 'curved']) {
      doc.setFeature(producer(mode: mode));
      final result = doc.evaluation.features[attachmentId]!;
      expect(result.state, FeatureState.failed);
      expect(result.issue, FeatureIssue.brokenAttachment);
      expect(result.support, isNull);
      expect(
        result.message,
        contains(mode == 'curved' ? 'no longer planar' : mode),
      );
      expect(result.outputs, isEmpty);
      doc.setFeature(producer());
      expect(doc.evaluation.features[attachmentId]!.state, FeatureState.valid);
    }
    doc.setFeature(producer(mode: 'failed'));
    expect(
      doc.evaluation.features[attachmentId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(
      doc.evaluation.features[attachmentId]!.message,
      contains('unavailable'),
    );
    doc.removeFeature(producerId);
    expect(
      doc.evaluation.features[attachmentId]!.issue,
      FeatureIssue.brokenAttachment,
    );
  });

  test(
    'a singular preferred axis breaks rather than choosing another axis',
    () {
      final doc = CadDocument(
        evaluators: evaluators,
        features: [
          producer(angle: math.pi / 2),
          attachment(),
        ],
      );
      expect(
        doc.evaluation.features[attachmentId]!.issue,
        FeatureIssue.brokenAttachment,
      );
      expect(doc.evaluation.features[attachmentId]!.message, contains('axis'));
    },
  );

  test(
    'axis value cannot mutate stored definition; body references rejected',
    () {
      final axis = Vector3(1, 0, 0);
      final support = PlanarSupport.face(
        reference: faceReference(),
        preferredDirection: axis,
      );
      axis.y = 20;
      support.preferredDirection!.z = 20;
      expect(support.preferredDirection, Vector3(1, 0, 0));
      expect(
        () => PlanarSupport.face(
          reference: OutputReference(
            featureId: producerId,
            key: 'body',
            kind: OutputKind.body,
          ),
          preferredDirection: axis,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'history undo/redo rebuilds attached frame and recovers lost reference',
    () {
      final controller = DocumentController(
        evaluators: evaluators,
        features: [producer(height: 2), attachment()],
      );
      addTearDown(controller.dispose);
      controller.setFeature(producer(height: 12));
      expect(
        controller.evaluation.features[attachmentId]!.support!.frame.origin.z,
        12,
      );
      controller.undo();
      expect(
        controller.evaluation.features[attachmentId]!.support!.frame.origin.z,
        2,
      );
      controller.redo();
      expect(
        controller.evaluation.features[attachmentId]!.support!.frame.origin.z,
        12,
      );
      controller.removeFeature(producerId);
      expect(
        controller.evaluation.features[attachmentId]!.issue,
        FeatureIssue.brokenAttachment,
      );
      controller.undo();
      expect(
        controller.evaluation.features[attachmentId]!.support!.frame.origin.z,
        12,
      );
    },
  );

  test('self and mutual face-support cycles never invoke evaluators', () {
    var evaluations = 0;
    List<FeatureOutput> evaluate(
      FeatureDefinition d,
      FeatureEvaluationContext c,
    ) {
      evaluations++;
      return [
        FeatureOutput(
          key: 'face',
          kind: OutputKind.face,
          geometry: rectangle(PlanarFrame.xy()),
        ),
      ];
    }

    final a = FeatureId('a'), b = FeatureId('b');
    final doc = CadDocument(
      evaluators: {'support': evaluate},
      features: [
        attachment(
          id: a,
          reference: faceReference(id: a),
        ),
      ],
    );
    expect(doc.evaluation.features[a]!.issue, FeatureIssue.cycle);
    doc.replaceFeatures([
      attachment(
        id: a,
        reference: faceReference(id: b),
      ),
      attachment(
        id: b,
        reference: faceReference(id: a),
      ),
      attachment(reference: faceReference(id: a)),
    ]);
    expect(doc.evaluation.features[a]!.issue, FeatureIssue.cycle);
    expect(doc.evaluation.features[b]!.issue, FeatureIssue.cycle);
    expect(
      doc.evaluation.features[attachmentId]!.issue,
      FeatureIssue.brokenAttachment,
    );
    expect(evaluations, 0);
  });
}
