import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:faust_cad_app_2/cad_scene/rendering/metal/metal_viewport_controller.dart';
import 'package:faust_cad_app_2/screens/cad_screen.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/feature_history_fixtures.dart';

class _SaveLocation extends FileSelectorPlatform {
  _SaveLocation(this.path);
  final String path;
  bool fail = false;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    if (fail) throw StateError('Save dialog unavailable.');
    return FileSaveLocation(path);
  }
}

// Compare the actual snackbar paragraph with an independently laid out reference
// using the native system font. Headless widget tests use a box font and cannot
// detect the glyph corruption reported from the macOS release build.
Future<void> verifyGlyphs(
  WidgetTester tester,
  GlobalKey root,
  String message,
) async {
  final text = find.text(message);
  expect(text, findsOneWidget);
  final boundary =
      root.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final offset = paragraph.localToGlobal(Offset.zero, ancestor: boundary);
  final bounds = offset & paragraph.size;
  final actualImage = await boundary.toImage();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final color = Theme.of(tester.element(text)).colorScheme.inverseSurface;
  canvas.drawRect(bounds.inflate(2), Paint()..color = color);
  final referenceText = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(minWidth: paragraph.size.width, maxWidth: paragraph.size.width);
  referenceText.paint(canvas, offset);
  final picture = recorder.endRecording();
  final referenceImage = await picture.toImage(
    actualImage.width,
    actualImage.height,
  );
  final actual = (await actualImage.toByteData())!;
  final reference = (await referenceImage.toByteData())!;
  var difference = 0, changed = 0, pixels = 0;
  for (
    var y = math.max(0, bounds.top.floor());
    y < math.min(actualImage.height, bounds.bottom.ceil());
    y++
  ) {
    for (
      var x = math.max(0, bounds.left.floor());
      x < math.min(actualImage.width, bounds.right.ceil());
      x++
    ) {
      final index = (y * actualImage.width + x) * 4;
      var largest = 0;
      for (var c = 0; c < 3; c++) {
        final delta =
            (actual.getUint8(index + c) - reference.getUint8(index + c)).abs();
        difference += delta;
        largest = math.max(largest, delta);
      }
      if (largest > 40) changed++;
      pixels++;
    }
  }
  referenceText.dispose();
  picture.dispose();
  referenceImage.dispose();
  actualImage.dispose();
  expect(difference / (pixels * 3), lessThan(2), reason: message);
  expect(changed / pixels, lessThan(.01), reason: message);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native export snackbars keep complete, correctly placed glyphs', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('step-rendering-');
    final file = File.fromUri(directory.uri.resolve('model.step'));
    final original = FileSelectorPlatform.instance;
    final selector = _SaveLocation(file.path);
    FileSelectorPlatform.instance = selector;
    final document = historyDocument();
    final root = GlobalKey();
    addTearDown(() {
      FileSelectorPlatform.instance = original;
      document.dispose();
      directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: root,
        child: MaterialApp(home: CadScreen(controller: document)),
      ),
    );
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.runAsync(() async {
        final callback = tester
            .widget<OutlinedButton>(find.byKey(const Key('export-step')))
            .onPressed!;
        await (callback as Future<void> Function())();
      });
      await tester.pumpAndSettle();
      expect(file.readAsStringSync(), startsWith('ISO-10303-21;'));
      await verifyGlyphs(tester, root, 'Exported 4 solid bodies to STEP.');
      ScaffoldMessenger.of(tester.element(find.byType(CadScreen)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
    }
    selector.fail = true;
    await tester.tap(find.byKey(const Key('export-step')));
    await tester.pumpAndSettle();
    await verifyGlyphs(
      tester,
      root,
      'STEP export failed: Bad state: Save dialog unavailable.',
    );
    // The Flutter chrome workaround must retain the native CAD Metal renderer.
    final environment = await MetalViewportController.channel
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment!['activeRenderers'], 1);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
  });
}
