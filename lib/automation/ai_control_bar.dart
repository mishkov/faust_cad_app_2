import 'package:flutter/material.dart';

class AiControlBar extends StatelessWidget {
  const AiControlBar({
    super.key,
    required this.active,
    required this.paused,
    required this.connected,
    required this.onEnable,
    required this.onStop,
    required this.onCopy,
    this.operation,
    this.error,
  });

  final bool active;
  final bool paused;
  final bool connected;
  final String? operation;
  final String? error;
  final VoidCallback? onEnable;
  final VoidCallback onStop;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Material(
    color: active
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            active
                ? 'AI is editing • ${operation == null ? 'Inspecting model' : 'Building geometry'}'
                : paused
                ? 'AI stopped'
                : connected
                ? 'MCP ready'
                : 'AI control off',
          ),
          if (active)
            FilledButton.icon(
              key: const Key('stop-ai'),
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop AI'),
            )
          else if (!connected || paused)
            OutlinedButton(
              key: const Key('enable-ai'),
              onPressed: onEnable,
              child: Text(paused ? 'Re-enable AI' : 'Enable MCP'),
            ),
          if (connected)
            TextButton(
              key: const Key('copy-mcp-connection'),
              onPressed: onCopy,
              child: const Text('Copy MCP connection'),
            ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
