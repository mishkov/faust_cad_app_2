import 'package:flutter/material.dart';

class SketchDimensionDialog extends StatefulWidget {
  const SketchDimensionDialog({
    super.key,
    required this.title,
    this.current,
    this.allowZero = false,
  });
  final String title;
  final double? current;
  final bool allowZero;
  @override
  State<SketchDimensionDialog> createState() => _SketchDimensionDialogState();
}

class _SketchDimensionDialogState extends State<SketchDimensionDialog> {
  late final _controller = TextEditingController(
    text: widget.current?.toString() ?? '',
  );
  String? _error;
  void _submit() {
    final value = double.tryParse(_controller.text);
    if (value == null ||
        !value.isFinite ||
        (widget.allowZero ? value < 0 : value <= 0)) {
      setState(
        () => _error = widget.allowZero
            ? 'Enter a finite value ≥ 0.'
            : 'Enter a positive finite value.',
      );
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('dimension-input'),
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(labelText: 'Model units', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Apply')),
    ],
  );
}
