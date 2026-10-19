import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../automation/ai_integration_controller.dart';

class AiIntegrationSettings extends StatefulWidget {
  const AiIntegrationSettings({super.key, required this.integration});
  final AiIntegrationController integration;

  @override
  State<AiIntegrationSettings> createState() => _AiIntegrationSettingsState();
}

class _AiIntegrationSettingsState extends State<AiIntegrationSettings> {
  final _form = GlobalKey<FormState>();
  late final _port = TextEditingController(text: '${widget.integration.port}');

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  void _toggle(bool value) {
    if (value) {
      if (!_form.currentState!.validate()) return;
      widget.integration.setPort(int.parse(_port.text));
      unawaited(widget.integration.enable());
    } else {
      unawaited(widget.integration.disable());
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.integration,
    builder: (context, _) {
      final integration = widget.integration;
      final ai = integration.automation;
      final status = integration.isBusy
          ? 'Updating connection…'
          : !integration.isEnabled
          ? 'Disabled'
          : ai.isActive
          ? 'AI is editing'
          : ai.paused
          ? 'AI stopped'
          : 'Ready';
      return Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI Integration',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Connect an AI assistant to Faust CAD using MCP.'),
            const SizedBox(height: 28),
            Card.outlined(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                key: const Key('enable-mcp'),
                title: const Text('Enable MCP'),
                subtitle: const Text(
                  'Allow a local AI client to inspect and edit this document.',
                ),
                value: integration.isEnabled,
                onChanged: integration.isBusy ? null : _toggle,
              ),
            ),
            const SizedBox(height: 24),
            Text('Connection', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: 240,
              child: TextFormField(
                key: const Key('mcp-port'),
                controller: _port,
                enabled: !integration.isBusy && !integration.isEnabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Local port',
                  helperText: '0 selects an available port.',
                  border: OutlineInputBorder(),
                ),
                validator: (text) {
                  final port = int.tryParse(text ?? '');
                  return port == null || port < 0 || port > 65535
                      ? 'Enter a port from 0 to 65535.'
                      : null;
                },
                onChanged: (text) {
                  final port = int.tryParse(text);
                  if (port != null && port >= 0 && port <= 65535) {
                    integration.setPort(port);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            Text('Status: $status', key: const Key('mcp-status')),
            if (integration.isBusy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (integration.endpoint != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  integration.endpoint!,
                  key: const Key('mcp-endpoint'),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('copy-mcp-connection'),
                onPressed: () => unawaited(
                  Clipboard.setData(ClipboardData(text: integration.endpoint!)),
                ),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy MCP connection'),
              ),
            ],
            if (integration.error != null) ...[
              const SizedBox(height: 12),
              Text(
                integration.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Editing control',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'During an AI session, model editing is locked. You can still inspect and rotate the scene. Stop AI cancels pending changes and keeps completed steps.',
            ),
            if (ai.isActive) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('settings-stop-ai'),
                onPressed: ai.stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop AI'),
              ),
            ] else if (integration.isEnabled && ai.paused) ...[
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('resume-ai'),
                onPressed: ai.enable,
                child: const Text('Re-enable AI'),
              ),
            ],
          ],
        ),
      );
    },
  );
}
