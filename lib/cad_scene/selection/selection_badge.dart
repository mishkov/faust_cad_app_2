import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'selection_measurement.dart';

class SelectionBadge extends StatefulWidget {
  const SelectionBadge({super.key, required this.measurement});

  final SelectionMeasurement measurement;

  @override
  State<SelectionBadge> createState() => _SelectionBadgeState();
}

class _SelectionBadgeState extends State<SelectionBadge> {
  Timer? _copiedTimer;
  bool _copied = false;
  int _copyGeneration = 0;

  @override
  void didUpdateWidget(covariant SelectionBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.measurement.kind != widget.measurement.kind ||
        !listEquals(oldWidget.measurement.values, widget.measurement.values)) {
      _copyGeneration++;
      _copiedTimer?.cancel();
      _copied = false;
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy(String value) async {
    final generation = ++_copyGeneration;
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on PlatformException {
      return;
    }
    if (!mounted || generation != _copyGeneration) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    String format(double value) => value != 0 && value.abs() < 0.001
        ? value.toStringAsPrecision(3)
        : value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.onSurface,
    );
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        container: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_copied) ...[
              Semantics(
                liveRegion: true,
                child: Material(
                  key: const Key('selection-copied'),
                  color: theme.colorScheme.surfaceContainerHigh,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text('copied', style: style),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Material(
              key: const Key('selection-badge-surface'),
              color: theme.colorScheme.surfaceContainerHigh,
              elevation: 3,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: DefaultTextStyle(
                  style: style,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        widget.measurement.kind == 'Edge'
                            ? Icons.straighten
                            : Icons.circle_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      Text(widget.measurement.kind),
                      for (final item in widget.measurement.values)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('${item.label} '),
                            Tooltip(
                              message: 'Double-click to copy',
                              child: IntrinsicWidth(
                                child: SelectableText(
                                  format(item.value),
                                  key: ValueKey(
                                    'selection-number-${item.label}',
                                  ),
                                  style: style,
                                  onSelectionChanged: (_, cause) {
                                    if (cause ==
                                        SelectionChangedCause.doubleTap) {
                                      unawaited(_copy(format(item.value)));
                                    }
                                  },
                                ),
                              ),
                            ),
                            const Text(' mm'),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
