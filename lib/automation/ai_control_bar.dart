import 'package:flutter/material.dart';

class AiControlBar extends StatelessWidget {
  const AiControlBar({
    super.key,
    required this.active,
    required this.paused,
    required this.onStop,
    required this.onOpenSettings,
    this.operation,
  });

  final bool active;
  final bool paused;
  final String? operation;
  final VoidCallback onStop;
  final VoidCallback onOpenSettings;

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
                : 'AI control off',
          ),
          if (active)
            FilledButton.icon(
              key: const Key('stop-ai'),
              onPressed: onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop AI'),
            ),
          TextButton(
            onPressed: onOpenSettings,
            child: const Text('AI Integration settings'),
          ),
        ],
      ),
    ),
  );
}
