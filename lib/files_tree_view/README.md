# FilesTreeView

An isolated, in-memory explorer. It does not read the filesystem or depend on the
CAD screen. Import the barrel with a prefix to avoid conflicts with `dart:io.File`:

```dart
import 'package:faust_cad_app_2/files_tree_view/files_tree_view.dart' as tree;
import 'package:flutter/material.dart';

final entries = <tree.FileTreeEntry>[
  tree.Folder(
    id: 'project',
    name: 'faust_cad_app_2',
    initiallyExpanded: true,
    children: [
      tree.Folder(
        id: 'lib',
        name: 'lib',
        initiallyExpanded: true,
        children: [
          const tree.File(
            id: 'main',
            name: 'main.dart',
            path: '/project/lib/main.dart',
            colorModifier: Colors.green, // Caller-supplied status color.
          ),
          const tree.File(
            id: 'model',
            name: 'part.step',
            type: tree.FileType.cad, // Optional explicit override.
          ),
        ],
      ),
    ],
  ),
];

// Place in a parent with bounded width and height, e.g. a sidebar in a Row.
SizedBox(
  width: 260,
  child: tree.FilesTreeView(
    entries: entries,
    onFilePicked: (file) {
      // Open or inspect file.id / file.path in the host application.
    },
  ),
);
```

- IDs must be nonempty, unique throughout the tree, and stable across refreshes.
  Names need not be unique. Paths are optional so virtual CAD entries work too.
- Entries are immutable. Folders defensively copy their children. Supply a new
  root-list snapshot when rebuilding; ordering is preserved without sorting.
- Expansion and selection are internal to each view and preserved by ID. New
  folders use `initiallyExpanded`; removed entries discard their state. Selection
  falls back to the nearest visible ancestor when an entry becomes hidden.
- `initialSelectedEntryId` applies only on first mount. It does not invoke the
  file callback. If the entry is hidden, its visible ancestor is selected.
- File clicks and Enter/Space invoke `onFilePicked`, including repeat picks.
  Folders toggle without invoking it. Keyboard navigation only moves selection.
- Up/Down and Home/End navigate visible rows. Right expands a folder or selects
  its first child. Left collapses a folder or selects its parent. Tab enters or
  leaves the tree. Modified keys are passed through to application shortcuts.
- `rowHeight` defaults to 24 and `indent` to 14. Colors follow the surrounding
  Flutter theme. `colorModifier` overrides label and default icon colors for both
  files and folders; no Git-specific meaning is imposed.
- `File.type` infers common extensions, including Dart, code, configuration,
  images, archives, and CAD formats. Unknown files have a generic icon. Pass an
  explicit `type` or an `iconBuilder(context, entry, expanded)` to customize.
  `FilesTreeIcon` is exported for fallback rendering from custom builders.
- `onFolderExpansionChanged` optionally observes expansion. Rows include
  accessible selection, expansion, and tap actions, path/name tooltips, truncated
  names, hover feedback, and keyboard focus outlines. Visible rows are built lazily.
- An empty tree displays `emptyMessage`, which defaults to "No files".

The component intentionally leaves filesystem loading, Git status calculation,
context menus, drag-and-drop, and integration with the CAD screen to its host.
