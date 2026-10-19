import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../automation/ai_integration_controller.dart';
import '../automation/automation_controller.dart';
import '../document/document_controller.dart';
import 'settings_dialog.dart';

@Preview(name: 'Settings • desktop', size: Size(1200, 850))
@Preview(name: 'Settings • small desktop', size: Size(800, 600))
Widget settingsPreview() => const _SettingsPreview();

class _SettingsPreview extends StatefulWidget {
  const _SettingsPreview();

  @override
  State<_SettingsPreview> createState() => _SettingsPreviewState();
}

class _SettingsPreviewState extends State<_SettingsPreview> {
  late final _document = DocumentController(evaluators: {});
  late final _automation = AutomationController(_document);
  late final _integration = AiIntegrationController(_automation);

  @override
  void dispose() {
    _integration.dispose();
    _automation.dispose();
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: SettingsDialog(integration: _integration)),
  );
}
