import 'package:faust_cad_app_2/automation/ai_integration_controller.dart';
import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:faust_cad_app_2/document/feature_id.dart';
import 'package:faust_cad_app_2/document/features/sketch_feature.dart';
import 'package:faust_cad_app_2/document/planar_support.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:faust_cad_app_2/settings/settings_dialog.dart';
import 'package:faust_cad_app_2/sketch/sketch_definition.dart';
import 'package:faust_cad_app_2/sketch_editor/sketch_workspace.dart';
import 'package:faust_cad_app_2/extrusion_editor/extrusion_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../automation/automation_controller_test.dart'
    show emptyDocument, washerSketch;

Future<void> openSettingsShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'settings button opens a large dialog with sections on the left',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = emptyDocument();
      await tester.pumpWidget(
        MaterialApp(home: CadScreen(controller: document)),
      );
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsOneWidget);
      final dialog = tester.getRect(find.byKey(const Key('settings-panel')));
      expect(dialog.width, 960);
      expect(dialog.height, 680);
      expect(
        tester.getRect(find.byKey(const Key('settings-ai-section'))).right,
        lessThan(tester.getRect(find.byKey(const Key('enable-mcp'))).left),
      );
      expect(find.byKey(const Key('enable-mcp')), findsOneWidget);
      expect(find.byKey(const Key('mcp-port')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      expect(document.features, isEmpty);
      await tester.pumpWidget(const SizedBox());
      document.dispose();
    },
  );

  testWidgets(
    'Command-comma is global, avoids duplicate dialogs and supports Escape',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CadScreen()));
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(find.byType(SettingsDialog), findsNothing);
      await openSettingsShortcut(tester);
      expect(find.byType(SettingsDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('mcp-port')));
      await openSettingsShortcut(tester);
      expect(find.byType(SettingsDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsDialog), findsNothing);
      await openSettingsShortcut(tester);
      expect(find.byType(SettingsDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await openSettingsShortcut(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final workspace in ['sketch', 'extrusion']) {
    testWidgets(
      'Command-comma works during $workspace editing and preserves the session',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final document = emptyDocument();
        final args = washerSketch();
        document.addFeature(
          SketchFeature.definition(
            id: FeatureId('washer'),
            sketch: SketchDefinition.fromParameters(
              support: const PlanarSupport.principal(PrincipalPlane.xy),
              parameters: {
                'version': 1,
                'points': args['points'],
                'segments': args['segments'],
                'circles': args['circles'],
                'retiredIds': [],
              },
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(home: CadScreen(controller: document)),
        );
        await tester.tap(
          find.byKey(
            Key(workspace == 'sketch' ? 'open-washer' : 'extrude-washer'),
          ),
        );
        await tester.pumpAndSettle();
        if (workspace == 'extrusion') {
          await tester.tap(find.byKey(const Key('extrusion-distance')));
        }
        final before = document.features;
        final undo = document.undoCount;
        await openSettingsShortcut(tester);
        expect(find.byType(SettingsDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('close-settings')));
        await tester.pumpAndSettle();
        expect(
          find.byType(
            workspace == 'sketch' ? SketchWorkspace : ExtrusionWorkspace,
          ),
          findsOneWidget,
        );
        expect(document.features, before);
        expect(document.undoCount, undo);
        await tester.pumpWidget(const SizedBox());
        document.dispose();
      },
    );
  }

  for (final size in [const Size(1280, 900), const Size(800, 600)]) {
    testWidgets(
      'settings fit $size and validate the port before enabling MCP',
      (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final document = emptyDocument();
        final ai = AutomationController(document);
        final integration = AiIntegrationController(ai);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SettingsDialog(integration: integration)),
          ),
        );
        await tester.enterText(find.byKey(const Key('mcp-port')), '99999');
        await tester.tap(find.byKey(const Key('enable-mcp')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a port from 0 to 65535.'), findsOneWidget);
        expect(integration.isEnabled, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        integration.dispose();
        ai.dispose();
        document.dispose();
      },
    );
  }

  testWidgets('settings display live Stop AI and restore editing control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final document = emptyDocument();
    final ai = AutomationController(document);
    final integration = AiIntegrationController(ai, port: 0);
    await tester.runAsync(() => integration.enable());
    expect(integration.isEnabled, isTrue);
    await ai.call('client', 'cad_begin', {});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsDialog(integration: integration)),
      ),
    );
    expect(find.text('Status: AI is editing'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('settings-stop-ai')));
    await tester.tap(find.byKey(const Key('settings-stop-ai')));
    await tester.pumpAndSettle();
    expect(document.isEditLocked, isFalse);
    expect(find.text('Status: AI stopped'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resume-ai')));
    await tester.pumpAndSettle();
    expect(ai.paused, isFalse);
    expect(find.text('Status: Ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => integration.disable());
    integration.dispose();
    ai.dispose();
    document.dispose();
  });
}
