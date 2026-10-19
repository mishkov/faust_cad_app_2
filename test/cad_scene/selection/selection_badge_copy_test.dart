import 'package:faust_cad_app_2/cad_scene/selection/selection_badge.dart';
import 'package:faust_cad_app_2/cad_scene/selection/selection_measurement.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const measurement = SelectionMeasurement('Hole', [
  (label: 'Radius', value: 0.125),
  (label: 'Height', value: 5),
]);
const radiusKey = ValueKey('selection-number-Radius');

Future<void> doubleClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.pump();
}

void main() {
  late List<String> copied;
  late bool failCopy;
  setUp(() {
    copied = [];
    failCopy = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              if (failCopy) {
                throw PlatformException(code: 'clipboard_unavailable');
              }
              copied.add((call.arguments as Map)['text'] as String);
              return null;
            case 'Clipboard.hasStrings':
              return {'value': copied.isNotEmpty};
            case 'Clipboard.getData':
              return {'text': copied.isEmpty ? '' : copied.last};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> showBadge(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      home: const Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SelectionBadge(measurement: measurement),
        ),
      ),
    ),
  );

  testWidgets(
    'double-click copies the complete decimal and shows feedback above',
    (tester) async {
      await showBadge(tester);
      final surface = find.byKey(const Key('selection-badge-surface'));
      final before = tester.getRect(surface);
      await doubleClick(tester, find.byKey(radiusKey));
      expect(copied, ['0.125']);
      expect(find.text('copied'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('selection-copied'))).bottom,
        lessThanOrEqualTo(before.top - 8),
      );
      expect(tester.getRect(surface), before);
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text('copied'), findsNothing);
      expect(find.byType(SelectionBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated double-click copies again and restarts feedback duration',
    (tester) async {
      await showBadge(tester);
      final number = find.byKey(radiusKey);
      await doubleClick(tester, number);
      await tester.pump(const Duration(milliseconds: 800));
      await doubleClick(tester, number);
      expect(copied, ['0.125', '0.125']);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('copied'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('copied'), findsNothing);
    },
  );

  testWidgets('dragging selects numeric text without triggering quick copy', (
    tester,
  ) async {
    await showBadge(tester);
    final number = find.byKey(radiusKey);
    final rect = tester.getRect(number);
    final mouse = await tester.startGesture(
      rect.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(rect.centerRight - const Offset(1, 0));
    await mouse.up();
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(of: number, matching: find.byType(EditableText)),
    );
    expect(editable.controller.selection.isCollapsed, isFalse);
    expect(copied, isEmpty);
    expect(find.text('copied'), findsNothing);
  });

  testWidgets('failed clipboard writes never show copied feedback', (
    tester,
  ) async {
    failCopy = true;
    await showBadge(tester);
    await doubleClick(tester, find.byKey(radiusKey));
    expect(copied, isEmpty);
    expect(find.text('copied'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing measurement clears feedback and pending timers dispose safely',
    (tester) async {
      await showBadge(tester);
      await doubleClick(tester, find.byKey(radiusKey));
      expect(find.text('copied'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SelectionBadge(
                measurement: SelectionMeasurement('Edge', [
                  (label: 'Length', value: 20),
                ]),
              ),
            ),
          ),
        ),
      );
      expect(find.text('copied'), findsNothing);
      expect(find.text('20'), findsOneWidget);
      await doubleClick(
        tester,
        find.byKey(const ValueKey('selection-number-Length')),
      );
      expect(copied.last, '20');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
