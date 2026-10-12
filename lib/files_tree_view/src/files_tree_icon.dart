import 'package:flutter/material.dart';

import '../models/file.dart';
import '../models/file_tree_entry.dart';
import '../models/file_type.dart';
import '../models/folder.dart';

/// The default icon renderer, also usable from a custom icon builder.
class FilesTreeIcon extends StatelessWidget {
  const FilesTreeIcon({super.key, required this.entry, this.expanded = false});

  final FileTreeEntry entry;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color) = switch (entry) {
      Folder() => (
        expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
        colors.onSurfaceVariant,
      ),
      File(:final type) => switch (type) {
        FileType.dart => (Icons.code, Colors.lightBlue.shade400),
        FileType.code => (Icons.code, colors.primary),
        FileType.json => (Icons.data_object, Colors.amber.shade700),
        FileType.yaml => (Icons.settings_outlined, Colors.purple.shade300),
        FileType.markdown => (Icons.article_outlined, colors.primary),
        FileType.text => (Icons.notes, colors.onSurfaceVariant),
        FileType.image => (Icons.image_outlined, Colors.teal.shade400),
        FileType.archive => (Icons.archive_outlined, Colors.brown.shade400),
        FileType.cad => (Icons.view_in_ar_outlined, Colors.orange.shade600),
        FileType.unknown => (
          Icons.insert_drive_file_outlined,
          colors.onSurfaceVariant,
        ),
      },
      _ => (Icons.insert_drive_file_outlined, colors.onSurfaceVariant),
    };
    return Icon(icon, size: 16, color: entry.colorModifier ?? color);
  }
}
