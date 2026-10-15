import 'dart:async';
import 'dart:io';

import 'package:faust_cad_app_2/cad_scene/cad_objects/cube.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/solid.dart';
import 'package:faust_cad_app_2/cad_scene/cad_primitivies/vertex.dart';
import 'package:faust_cad_app_2/document/document_controller.dart';
import 'package:faust_cad_app_2/document/feature_definition.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/cube_feature.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/step_export/step_export_button.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

class _FileSelector extends FileSelectorPlatform {
  var calls = 0;
  SaveDialogOptions? lastOptions;
  List<XTypeGroup>? lastTypes;
  Future<FileSaveLocation?> Function() response = () async => null;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) {
    calls++;
    lastOptions = options;
    lastTypes = acceptedTypeGroups;
    return response();
  }
}

void main() {
  late _FileSelector selector;
  final solids = Cube(centerPosition: Vertex(Vector3.zero()), size: 2).build();
  final button = find.byKey(const Key('export-step'));
  OutlinedButton control(WidgetTester tester) => tester.widget(button);

  Future<void> mount(WidgetTester tester, {List<Solid>? bodies}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StepExportButton(solids: bodies ?? solids)),
        ),
      );

  setUp(() {
    final original = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = original);
    selector = _FileSelector();
    FileSelectorPlatform.instance = selector;
  });

  testWidgets('empty document disables export despite viewer fixtures', (
    tester,
  ) async {
    final document = DocumentController(
      evaluators: {CubeFeature.type: CubeFeature.evaluate},
    );
    addTearDown(document.dispose);
    await tester.pumpWidget(MaterialApp(home: CadScreen(controller: document)));
    expect(control(tester).onPressed, isNull);
    document.addFeature(
      FeatureDefinition(
        id: FeatureId('cube'),
        type: CubeFeature.type,
        parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 2},
      ),
    );
    await tester.pump();
    expect(control(tester).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel is silent and busy state prevents duplicate exports', (
    tester,
  ) async {
    final pending = Completer<FileSaveLocation?>();
    selector.response = () => pending.future;
    await mount(tester);
    await tester.tap(button);
    await tester.pump();
    expect(control(tester).onPressed, isNull);
    expect(selector.calls, 1);
    expect(selector.lastOptions!.suggestedName, 'model.step');
    expect(selector.lastTypes!.single.extensions, ['step', 'stp']);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(control(tester).onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'saves a document revision, excluding fixtures and failed outputs',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('faust-step-test-');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File.fromUri(folder.uri.resolve('model.step'));
      final document = DocumentController(
        evaluators: {CubeFeature.type: CubeFeature.evaluate},
        features: [
          for (final id in ['first', 'second', 'failed'])
            FeatureDefinition(
              id: FeatureId(id),
              type: CubeFeature.type,
              parameters: {'x': 0, 'y': 0, 'z': 0, 'size': 2},
            ),
        ],
      );
      addTearDown(document.dispose);
      // Retained diagnostic geometry from the third cube must not be exported.
      document.updateParameters(FeatureId('failed'), {'size': -1});
      final pending = Completer<FileSaveLocation?>();
      selector.response = () => pending.future;
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      await tester.runAsync(() async {
        final save = (control(tester).onPressed! as Future<void> Function())();
        document.removeFeature(FeatureId('second'));
        pending.complete(FileSaveLocation(file.path));
        await save;
      });
      await tester.pumpAndSettle();
      final data = file.readAsStringSync();
      expect(data, startsWith('ISO-10303-21;'));
      expect(RegExp(r'=MANIFOLD_SOLID_BREP\(').allMatches(data), hasLength(2));
      expect(find.text('Exported 2 solid bodies to STEP.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dialog and write failures report errors and allow retry', (
    tester,
  ) async {
    selector.response = () async => throw StateError('Dialog unavailable');
    await mount(tester);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('STEP export failed:'), findsOneWidget);
    expect(control(tester).onPressed, isNotNull);
    selector.response = () async =>
        const FileSaveLocation('/missing-faust-directory/model.step');
    await tester.runAsync(() async {
      await (control(tester).onPressed! as Future<void> Function())();
    });
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(control(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount safely handles a pending dialog', (tester) async {
    final pending = Completer<FileSaveLocation?>();
    selector.response = () => pending.future;
    await mount(tester);
    await tester.tap(button);
    await tester.pumpWidget(const SizedBox());
    pending.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
