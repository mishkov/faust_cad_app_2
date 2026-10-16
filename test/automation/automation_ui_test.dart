import 'package:faust_cad_app_2/automation/ai_control_bar.dart';
import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:faust_cad_app_2/cad_scene/cad_scene.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'automation_controller_test.dart' show emptyDocument, washerSketch, data;

void main() {
  testWidgets(
    'AI locks mutation controls and shortcuts; orbit and Stop remain usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = emptyDocument();
      final ai = AutomationController(document);
      await tester.pumpWidget(
        MaterialApp(
          home: CadScreen(controller: document, automation: ai),
        ),
      );
      final initial = tester
          .widget<CadScene>(find.byType(CadScene))
          .cameraConfig;
      final session = data(
        await ai.call('client', 'cad_begin', {}),
      )['sessionId'];
      await tester.pump();
      expect(find.textContaining('AI is editing'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('new-sketch')))
            .onPressed,
        isNull,
      );
      expect(document.undo, throwsStateError);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(tester.takeException(), isNull);
      final scene = find.byType(CadScene);
      final location = tester.getCenter(scene);
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(position: location),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          position: location,
          pan: const Offset(40, 20),
          panDelta: const Offset(40, 20),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(position: location),
      );
      await tester.pump();
      final moved = tester.widget<CadScene>(scene).cameraConfig;
      expect(moved.yaw, isNot(initial.yaw));
      await tester.tap(find.byKey(const Key('stop-ai')));
      await tester.pump();
      expect(document.isEditLocked, isFalse);
      expect(find.text('AI stopped'), findsOneWidget);
      final denied = await ai.call('client', 'cad_set_sketch', {
        'sessionId': session,
        'requestId': 'late',
        'expectedRevision': document.evaluation.revision,
        ...washerSketch(),
      });
      expect(denied['isError'], isTrue);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('new-sketch')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      ai.dispose();
      document.dispose();
    },
  );

  testWidgets('compact AI controls wrap without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: AiControlBar(
              active: true,
              paused: false,
              connected: true,
              onEnable: () {},
              onStop: () {},
              onCopy: () {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('stop-ai')), findsOneWidget);
  });
}
