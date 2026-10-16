import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../cad_scene/cad_primitivies/solid.dart';
import 'step_exporter.dart';

class StepExportButton extends StatefulWidget {
  const StepExportButton({super.key, required this.solids});

  final List<Solid> solids;

  @override
  State<StepExportButton> createState() => _StepExportButtonState();
}

class _StepExportButtonState extends State<StepExportButton> {
  var _saving = false;

  Future<void> _export() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Capture a complete revision before the asynchronous native dialog opens.
      final count = widget.solids.length;
      final data = const StepExporter().exportSolids(widget.solids);
      final location = await getSaveLocation(
        suggestedName: 'model.step',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'STEP', extensions: ['step', 'stp']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(data)),
        mimeType: 'application/step',
        name: 'model.step',
      ).saveTo(location.path);
      if (!mounted) return;
      _message(
        'Exported $count solid ${count == 1 ? 'body' : 'bodies'} to STEP.',
      );
    } catch (error) {
      if (mounted) _message('STEP export failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.solids.isEmpty
        ? 'Create a solid body to export.'
        : 'Export document solids. One model unit = one millimeter.',
    child: OutlinedButton.icon(
      key: const Key('export-step'),
      onPressed: _saving || widget.solids.isEmpty ? null : _export,
      icon: const Icon(Icons.file_download_outlined, size: 18),
      label: Text(_saving ? 'Exporting…' : 'Export STEP'),
    ),
  );
}
