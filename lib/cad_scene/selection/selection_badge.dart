import 'package:flutter/material.dart';

import 'selection_measurement.dart';

class SelectionBadge extends StatelessWidget {
  const SelectionBadge({super.key, required this.measurement});

  final SelectionMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    String format(double value) => value != 0 && value.abs() < 0.001
        ? value.toStringAsPrecision(3)
        : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    final labels = [
      measurement.kind,
      for (final item in measurement.values)
        '${item.label} ${format(item.value)} mm',
    ];
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: labels.join(', '),
      child: ExcludeSemantics(
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          elevation: 3,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: DefaultTextStyle(
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.onSurface,
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    measurement.kind == 'Edge'
                        ? Icons.straighten
                        : Icons.circle_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  for (final label in labels) Text(label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
