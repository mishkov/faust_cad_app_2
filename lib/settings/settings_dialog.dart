import 'package:flutter/material.dart';

import '../automation/ai_integration_controller.dart';
import 'ai_integration_settings.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key, required this.integration});
  final AiIntegrationController integration;

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('settings-dialog'),
    insetPadding: const EdgeInsets.all(32),
    constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 720),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      key: const Key('settings-panel'),
      width: 960,
      height: 680,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('close-settings'),
                  tooltip: 'Close settings',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: constraints.maxWidth >= 800 ? 220 : 184,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          ListTile(
                            key: const Key('settings-ai-section'),
                            selected: true,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            leading: const Icon(Icons.auto_awesome_outlined),
                            title: const Text('AI Integration'),
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      key: const Key('settings-content'),
                      padding: const EdgeInsets.all(28),
                      child: AiIntegrationSettings(integration: integration),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
