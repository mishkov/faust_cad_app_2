import 'dart:io';

import 'package:faust_cad_app_2/automation/ai_integration_controller.dart';
import 'package:faust_cad_app_2/automation/automation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'automation_controller_test.dart' show emptyDocument;

void main() {
  test(
    'disable revokes editing and re-enable establishes a new local connection',
    () async {
      final document = emptyDocument();
      final ai = AutomationController(document);
      final integration = AiIntegrationController(ai, port: 0);
      try {
        await integration.enable();
        final endpoint = integration.endpoint;
        expect(endpoint, startsWith('ws://127.0.0.1:'));
        expect(() => integration.setPort(12345), throwsStateError);
        await ai.call('client', 'cad_begin', {});
        expect(document.isEditLocked, isTrue);
        await integration.disable();
        expect(document.isEditLocked, isFalse);
        expect(integration.endpoint, isNull);
        await integration.enable();
        expect(integration.isEnabled, isTrue);
        expect(integration.endpoint, isNot(endpoint));
        expect(integration.error, isNull);
      } finally {
        await integration.disable();
        integration.dispose();
        ai.dispose();
        document.dispose();
      }
    },
  );

  test('port collision is recoverable without restarting the app', () async {
    final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final document = emptyDocument();
    final ai = AutomationController(document);
    final integration = AiIntegrationController(ai, port: blocker.port);
    try {
      await integration.enable();
      expect(integration.error, isNotNull);
      expect(integration.isEnabled, isFalse);
      await blocker.close(force: true);
      await integration.enable();
      expect(integration.error, isNull);
      expect(integration.isEnabled, isTrue);
    } finally {
      await blocker.close(force: true);
      await integration.disable();
      integration.dispose();
      ai.dispose();
      document.dispose();
    }
  });

  test('MCP cannot acquire ownership during a human editing session', () async {
    final document = emptyDocument();
    final ai = AutomationController(document);
    document.beginEditSession();
    expect((await ai.call('client', 'cad_begin', {}))['isError'], isTrue);
    expect(document.isEditLocked, isFalse);
    document.cancelEditSession();
    expect((await ai.call('client', 'cad_begin', {}))['isError'], isNull);
    ai.dispose();
    document.dispose();
  });
}
