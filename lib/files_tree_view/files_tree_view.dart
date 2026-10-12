import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/file.dart';
import 'models/file_tree_entry.dart';
import 'models/folder.dart';
import 'src/files_tree_icon.dart';
import 'src/files_tree_row.dart';

export 'models/file.dart';
export 'models/file_tree_entry.dart';
export 'models/file_type.dart';
export 'models/folder.dart';
export 'src/files_tree_icon.dart';

typedef FilesTreeIconBuilder = Widget Function(
  BuildContext context,
  FileTreeEntry entry,
  bool expanded,
);

/// A scrollable, single-selection explorer with no disk IO or CAD dependencies.
/// Supply immutable snapshots in the desired display order and bounded height.
///
/// Clicking a file or pressing Enter/Space on it invokes [onFilePicked]. Folder
/// activation toggles expansion. Arrows and Home/End move through visible rows;
/// Left/Right collapse/expand folders or move to a parent/first child.
class FilesTreeView extends StatefulWidget {
  const FilesTreeView({
    super.key,
    required this.entries,
    required this.onFilePicked,
    this.initialSelectedEntryId,
    this.iconBuilder,
    this.onFolderExpansionChanged,
    this.rowHeight = 24,
    this.indent = 14,
    this.autofocus = false,
    this.emptyMessage = 'No files',
  }) : assert(rowHeight >= 20),
       assert(indent >= 0);

  final List<FileTreeEntry> entries;
  final ValueChanged<File> onFilePicked;

  /// Initial selection only. Subsequent updates preserve selection by ID.
  final String? initialSelectedEntryId;
  final FilesTreeIconBuilder? iconBuilder;
  final void Function(Folder folder, bool expanded)? onFolderExpansionChanged;
  final double rowHeight;
  final double indent;
  final bool autofocus;
  final String emptyMessage;

  @override
  State<FilesTreeView> createState() => _FilesTreeViewState();
}

// Kept with its widget because this state is an implementation detail of it.
class _FilesTreeViewState extends State<FilesTreeView> {
  final _focusNode = FocusNode(debugLabel: 'FilesTreeView');
  final _scrollController = ScrollController();
  final _expanded = <String>{};
  Map<String, FileTreeEntry> _entriesById = {};
  Map<String, String> _parentById = {};
  List<({FileTreeEntry entry, int depth})> _visible = [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSelectedEntryId;
    _updateEntries();
  }

  @override
  void didUpdateWidget(FilesTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateEntries();
  }

  void _updateEntries() {
    final entries = <String, FileTreeEntry>{};
    final parents = <String, String>{};
    void visit(List<FileTreeEntry> children, String? parent) {
      for (final entry in children) {
        if (entries.containsKey(entry.id)) {
          throw ArgumentError('Duplicate FilesTreeView entry ID: ${entry.id}');
        }
        entries[entry.id] = entry;
        if (parent != null) parents[entry.id] = parent;
        if (entry is Folder) {
          if (_entriesById[entry.id] is! Folder && entry.initiallyExpanded) {
            _expanded.add(entry.id);
          }
          visit(entry.children, entry.id);
        }
      }
    }

    visit(widget.entries, null);
    _entriesById = entries;
    _parentById = parents;
    _expanded.removeWhere((id) => entries[id] is! Folder);
    if (!entries.containsKey(_selectedId)) _selectedId = null;
    _updateVisible();
  }

  void _updateVisible() {
    final visible = <({FileTreeEntry entry, int depth})>[];
    void visit(List<FileTreeEntry> entries, int depth) {
      for (final entry in entries) {
        visible.add((entry: entry, depth: depth));
        if (entry is Folder && _expanded.contains(entry.id)) {
          visit(entry.children, depth + 1);
        }
      }
    }

    visit(widget.entries, 0);
    _visible = visible;
    // If an update or collapse hides the selected entry, select its nearest
    // visible ancestor rather than leave keyboard navigation on a hidden row.
    final visibleIds = visible.map((row) => row.entry.id).toSet();
    while (_selectedId != null && !visibleIds.contains(_selectedId)) {
      _selectedId = _parentById[_selectedId];
    }
  }

  void _select(String id) {
    setState(() => _selectedId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = _visible.indexWhere((row) => row.entry.id == _selectedId);
      if (index < 0) return;
      final position = _scrollController.position;
      final top = 4 + index * widget.rowHeight;
      final bottom = top + widget.rowHeight;
      final target = top < position.pixels
          ? top
          : bottom > position.pixels + position.viewportDimension
          ? bottom - position.viewportDimension
          : position.pixels;
      _scrollController.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  void _setExpanded(Folder folder, bool expanded) {
    setState(() {
      if (expanded) {
        _expanded.add(folder.id);
      } else {
        _expanded.remove(folder.id);
      }
      _updateVisible();
    });
    widget.onFolderExpansionChanged?.call(folder, expanded);
  }

  void _activate(FileTreeEntry entry) {
    _focusNode.requestFocus();
    _select(entry.id);
    if (entry is Folder) {
      _setExpanded(entry, !_expanded.contains(entry.id));
    } else if (entry is File) {
      widget.onFilePicked(entry);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _visible.isEmpty) {
      return KeyEventResult.ignored;
    }
    // Leave application shortcuts such as Cmd+1 to the enclosing screen.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final index = _visible.indexWhere((row) => row.entry.id == _selectedId);
    final entry = index < 0 ? null : _visible[index].entry;
    if (key == LogicalKeyboardKey.arrowDown) {
      _select(_visible[(index + 1).clamp(0, _visible.length - 1)].entry.id);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _select(
        _visible[index < 0 ? _visible.length - 1 : (index - 1).clamp(0, index)]
            .entry
            .id,
      );
    } else if (key == LogicalKeyboardKey.home) {
      _select(_visible.first.entry.id);
    } else if (key == LogicalKeyboardKey.end) {
      _select(_visible.last.entry.id);
    } else if (key == LogicalKeyboardKey.arrowRight && entry != null) {
      if (entry is Folder) {
        if (!_expanded.contains(entry.id)) {
          _setExpanded(entry, true);
        } else if (entry.children.isNotEmpty) {
          _select(entry.children.first.id);
        }
      }
    } else if (key == LogicalKeyboardKey.arrowLeft && entry != null) {
      if (entry is Folder && _expanded.contains(entry.id)) {
        _setExpanded(entry, false);
      } else {
        final parentId = _parentById[entry.id];
        if (parentId != null) _select(parentId);
      }
    } else if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) &&
        entry != null) {
      _activate(entry);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _onKeyEvent,
        onFocusChange: (_) => setState(() {}),
        child: _visible.isEmpty
            ? Center(
                child: Text(
                  widget.emptyMessage,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            : Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemExtent: widget.rowHeight,
                  itemCount: _visible.length,
                  itemBuilder: (context, index) {
                    final row = _visible[index];
                    final expanded = _expanded.contains(row.entry.id);
                    return FilesTreeRow(
                      key: ValueKey(row.entry.id),
                      entry: row.entry,
                      depth: row.depth,
                      indent: widget.indent,
                      expanded: expanded,
                      selected: _selectedId == row.entry.id,
                      focused: _focusNode.hasFocus,
                      icon:
                          widget.iconBuilder?.call(
                            context,
                            row.entry,
                            expanded,
                          ) ??
                          FilesTreeIcon(entry: row.entry, expanded: expanded),
                      onTap: () => _activate(row.entry),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
