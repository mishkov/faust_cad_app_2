import 'package:flutter/material.dart';

import '../document/document_controller.dart';
import '../document/feature_definition.dart';
import '../document/feature_id.dart';
import '../document/feature_result.dart';
import '../document/features/extrude_feature.dart';
import '../document/features/sketch_feature.dart';
import 'feature_history.dart';
import 'feature_name_dialog.dart';

class FeatureHistoryPanel extends StatelessWidget {
  const FeatureHistoryPanel({
    super.key,
    required this.document,
    required this.selectedId,
    required this.onSelected,
    required this.onOpenSketch,
    required this.onEditExtrusion,
    required this.onExtrudeSketch,
  });

  final DocumentController document;
  final FeatureId? selectedId;
  final ValueChanged<FeatureId> onSelected;
  final ValueChanged<FeatureId> onOpenSketch;
  final ValueChanged<FeatureId> onEditExtrusion;
  final ValueChanged<FeatureId> onExtrudeSketch;

  Future<void> _rename(BuildContext context, FeatureDefinition feature) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) =>
          FeatureNameDialog(initialName: FeatureHistory.name(feature)),
    );
    if (context.mounted &&
        result != null &&
        !document.isEditLocked &&
        !document.hasActiveTransaction &&
        document.features.any((f) => f.id == feature.id)) {
      document.renameFeature(feature.id, result);
    }
  }

  Future<void> _delete(BuildContext context, FeatureDefinition feature) async {
    // Observe publications even while the confirmation is open so its impact
    // list follows undo/redo or other document edits.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: document,
        builder: (context, _) {
          final current = document.features
              .where((f) => f.id == feature.id)
              .firstOrNull;
          final affected = FeatureHistory.affectedDependents(
            document.features,
            feature.id,
          );
          return AlertDialog(
            title: Text('Delete ${FeatureHistory.name(current ?? feature)}?'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Only this feature will be deleted. Dependents keep their '
                      'identities and references and may become failed or blocked. '
                      'Undo restores the feature and rebuilds its dependents.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      affected.isEmpty
                          ? 'No dependent features.'
                          : 'Affected dependents (${affected.length}):',
                    ),
                    for (final dependent in affected)
                      Text(
                        '• ${FeatureHistory.name(dependent)} (${dependent.id})',
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const Key('confirm-delete'),
                onPressed:
                    current == null ||
                        document.hasActiveTransaction ||
                        document.isEditLocked
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Delete feature'),
              ),
            ],
          );
        },
      ),
    );
    if (context.mounted &&
        confirmed == true &&
        !document.isEditLocked &&
        !document.hasActiveTransaction &&
        document.features.any((f) => f.id == feature.id)) {
      document.removeFeature(
        feature.id,
        label: 'Delete ${FeatureHistory.name(feature)}',
      );
    }
  }

  Widget _item(BuildContext context, FeatureDefinition feature, int index) {
    final result = document.evaluation.features[feature.id]!;
    final selected = selectedId == feature.id;
    final features = {for (final f in document.features) f.id: f};
    final color = switch (result.state) {
      FeatureState.valid => Colors.green.shade700,
      FeatureState.failed => Theme.of(context).colorScheme.error,
      FeatureState.blocked => Colors.orange.shade800,
    };
    final editable = !document.hasActiveTransaction && !document.isEditLocked;
    return Card(
      key: Key('history-${feature.id.value}'),
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: () => onSelected(feature.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                selected: selected,
                button: true,
                child: Text(
                  '${index + 1}. ${FeatureHistory.name(feature)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${FeatureHistory.typeName(feature.type)} • ${result.state.name}',
                style: TextStyle(color: color),
              ),
              Text(
                feature.dependencies.isEmpty
                    ? 'Dependencies: none'
                    : 'Dependencies: ${feature.dependencies.map((id) => features[id] == null ? '$id (missing)' : FeatureHistory.name(features[id]!)).join(', ')}',
              ),
              if (result.issue != null)
                Text(
                  'Issue: ${result.issue!.name}',
                  style: TextStyle(color: color),
                ),
              if (result.message != null)
                Tooltip(
                  message: result.message!,
                  child: Text(
                    result.message!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color),
                  ),
                ),
              if (feature.type == ExtrudeFeature.type)
                Text(
                  'Distance: ${feature.parameters['distance']} • Reverse: ${feature.parameters['reverse']}',
                ),
              if (feature.type == SketchFeature.type ||
                  feature.type == ExtrudeFeature.type)
                Wrap(
                  spacing: 4,
                  children: [
                    if (feature.type == SketchFeature.type) ...[
                      TextButton(
                        key: Key('open-${feature.id.value}'),
                        onPressed: editable
                            ? () => onOpenSketch(feature.id)
                            : null,
                        child: const Text('Open sketch'),
                      ),
                      TextButton(
                        key: Key('extrude-${feature.id.value}'),
                        onPressed:
                            editable && result.state == FeatureState.valid
                            ? () => onExtrudeSketch(feature.id)
                            : null,
                        child: const Text('Extrude'),
                      ),
                    ],
                    if (feature.type == ExtrudeFeature.type)
                      TextButton(
                        key: Key('edit-${feature.id.value}'),
                        onPressed: editable
                            ? () => onEditExtrusion(feature.id)
                            : null,
                        child: const Text('Edit extrusion'),
                      ),
                  ],
                ),
              if (selected) ...[
                Text('ID: ${feature.id.value}'),
                if (feature.support != null)
                  Text(
                    feature.support!.reference == null
                        ? 'Support: ${feature.support!.principalPlane!.name.toUpperCase()}'
                        : 'Attachment: ${FeatureHistory.referenceLabel(feature.support!.reference!, document.features)}',
                  ),
                for (final input in feature.inputs.entries)
                  Text(
                    'Input ${input.key}: ${FeatureHistory.referenceLabel(input.value, document.features)}',
                  ),
                Wrap(
                  children: [
                    TextButton.icon(
                      key: Key('rename-${feature.id.value}'),
                      onPressed: editable
                          ? () => _rename(context, feature)
                          : null,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Rename'),
                    ),
                    TextButton.icon(
                      key: Key('delete-${feature.id.value}'),
                      onPressed: editable
                          ? () => _delete(context, feature)
                          : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: document,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Feature history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text('Authored order'),
            ],
          ),
        ),
        Expanded(
          child: document.features.isEmpty
              ? const Center(child: Text('No features yet. Create a sketch.'))
              : ListView(
                  key: const Key('feature-history-list'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (var i = 0; i < document.features.length; i++)
                      _item(context, document.features[i], i),
                  ],
                ),
        ),
      ],
    ),
  );
}
