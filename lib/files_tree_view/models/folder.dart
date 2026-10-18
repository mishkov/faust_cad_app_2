import 'file_tree_entry.dart';

/// Children retain the supplied order. The list is copied and made immutable.
class Folder extends FileTreeEntry {
  Folder({
    required super.id,
    required super.name,
    super.path,
    super.colorModifier,
    List<FileTreeEntry> children = const [],
    this.initiallyExpanded = false,
  }) : children = List.unmodifiable(children);

  final List<FileTreeEntry> children;

  /// Used when this folder ID first appears in a view. Rebuilds preserve the
  /// user's expansion choice, even if a new Folder instance replaces this one.
  final bool initiallyExpanded;
}
