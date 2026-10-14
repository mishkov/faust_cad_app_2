import 'package:flutter/material.dart';

class FeatureNameDialog extends StatefulWidget {
  const FeatureNameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<FeatureNameDialog> createState() => _FeatureNameDialogState();
}

// The widget/state pair own the form and its text-controller lifecycle.
class _FeatureNameDialogState extends State<FeatureNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);

  void _confirm() {
    if (_form.currentState!.validate()) Navigator.pop(context, _name.text);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename feature'),
    content: Form(
      key: _form,
      child: TextFormField(
        key: const Key('feature-name'),
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter a name.' : null,
        onFieldSubmitted: (_) => _confirm(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('confirm-rename'),
        onPressed: _confirm,
        child: const Text('Rename'),
      ),
    ],
  );
}
