import 'package:flutter/material.dart';

import '../models/file_tree_entry.dart';
import '../models/folder.dart';

/// A compact explorer row. Keyboard focus belongs to the enclosing tree.
class FilesTreeRow extends StatelessWidget {
  const FilesTreeRow({
    super.key,
    required this.entry,
    required this.depth,
    required this.indent,
    required this.expanded,
    required this.selected,
    required this.focused,
    required this.icon,
    required this.onTap,
  });

  final FileTreeEntry entry;
  final int depth;
  final double indent;
  final bool expanded;
  final bool selected;
  final bool focused;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isFolder = entry is Folder;
    return Semantics(
      label: entry.name,
      button: true,
      selected: selected,
      expanded: isFolder ? expanded : null,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: entry.path ?? entry.name,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? colors.primary.withValues(alpha: 0.14) : null,
            border: Border.all(
              color: selected && focused ? colors.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: InkWell(
            onTap: onTap,
            canRequestFocus: false,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: EdgeInsets.only(left: 4 + depth * indent, right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: isFolder
                        ? Icon(
                            expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                            size: 18,
                            color: colors.onSurfaceVariant,
                          )
                        : null,
                  ),
                  SizedBox(width: 18, height: 18, child: Center(child: icon)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        color: entry.colorModifier ?? colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
