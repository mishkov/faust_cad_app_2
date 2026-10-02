import 'package:faust_cad_app_2/files_tree_view/files_tree_view.dart' as tree;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const mainFile = tree.File(
  id: 'main',
  name: 'main.dart',
  path: '/project/lib/main.dart',
);
const configFile = tree.File(id: 'config', name: 'pubspec.yaml');

List<tree.FileTreeEntry> entries({bool expanded = false}) => [
  tree.Folder(
    id: 'lib',
    name: 'lib',
    initiallyExpanded: expanded,
    children: [
      mainFile,
      tree.Folder(
        id: 'nested',
        name: 'nested',
        children: [const tree.File(id: 'part', name: 'part.step')],
      ),
    ],
  ),
  configFile,
];

Future<void> pumpTree(
  WidgetTester tester, {
  required List<tree.FileTreeEntry> entries,
  ValueChanged<tree.File>? onFilePicked,
  void Function(tree.Folder, bool)? onExpansion,
  tree.FilesTreeIconBuilder? iconBuilder,
  String? selectedId,
  ThemeData? theme,
  double width = 260,
  double height = 180,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: tree.FilesTreeView(
              entries: entries,
              onFilePicked: onFilePicked ?? (_) {},
              onFolderExpansionChanged: onExpansion,
              iconBuilder: iconBuilder,
              initialSelectedEntryId: selectedId,
              autofocus: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  test('file types are inferred case-insensitively and can be overridden', () {
    expect(mainFile.type, tree.FileType.dart);
    expect(configFile.type, tree.FileType.yaml);
    for (final (name, type) in [
      ('part.STEP', tree.FileType.cad),
      ('settings.jsonc', tree.FileType.json),
      ('README.md', tree.FileType.markdown),
      ('icon.SVG', tree.FileType.image),
      ('archive.tar.gz', tree.FileType.archive),
      ('app.tsx', tree.FileType.code),
      ('.gitignore', tree.FileType.text),
      ('LICENSE', tree.FileType.text),
      ('data.bin', tree.FileType.unknown),
      ('no-extension', tree.FileType.unknown),
    ]) {
      expect(tree.FileType.fromName(name), type, reason: name);
    }
    const file = tree.File(
      id: 'override',
      name: 'main.dart',
      type: tree.FileType.text,
    );
    expect(file.type, tree.FileType.text);
  });

  test('folder children are independent of input and immutable', () {
    final input = <tree.FileTreeEntry>[mainFile];
    final folder = tree.Folder(id: 'lib', name: 'lib', children: input);
    input.clear();
    expect(folder.children, [mainFile]);
    expect(() => folder.children.clear(), throwsUnsupportedError);
  });

  testWidgets('folder activation toggles children; only files invoke picks', (
    tester,
  ) async {
    final picked = <tree.File>[];
    final expansions = <(String, bool)>[];
    await pumpTree(
      tester,
      entries: entries(),
      onFilePicked: picked.add,
      onExpansion: (folder, expanded) => expansions.add((folder.id, expanded)),
    );
    expect(find.text('main.dart'), findsNothing);
    await tester.tap(find.text('lib'));
    await tester.pump();
    expect(find.text('main.dart'), findsOneWidget);
    expect(picked, isEmpty);
    expect(expansions, [('lib', true)]);
    await tester.tap(find.text('main.dart'));
    await tester.pump();
    await tester.tap(find.text('main.dart'));
    expect(picked, [same(mainFile), same(mainFile)]);
    await tester.tap(find.text('lib'));
    await tester.pump();
    expect(find.text('main.dart'), findsNothing);
    expect(expansions.last, ('lib', false));
  });

  testWidgets('arrows navigate hierarchy; Enter and Space pick files', (
    tester,
  ) async {
    final picked = <tree.File>[];
    await pumpTree(tester, entries: entries(), onFilePicked: picked.add);
    await key(tester, LogicalKeyboardKey.home);
    await key(tester, LogicalKeyboardKey.arrowRight); // Expand lib.
    await key(tester, LogicalKeyboardKey.arrowRight); // Select main.
    expect(picked, isEmpty);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked, [mainFile]);
    await key(tester, LogicalKeyboardKey.arrowDown); // Select nested.
    await key(tester, LogicalKeyboardKey.space); // Expand nested.
    await key(tester, LogicalKeyboardKey.arrowRight); // Select part.
    await key(tester, LogicalKeyboardKey.space);
    expect(picked.last.id, 'part');
    await key(tester, LogicalKeyboardKey.arrowLeft); // Select nested.
    await key(tester, LogicalKeyboardKey.arrowLeft); // Collapse nested.
    expect(find.text('part.step'), findsNothing);
    await key(tester, LogicalKeyboardKey.arrowLeft); // Select lib.
    await key(tester, LogicalKeyboardKey.arrowLeft); // Collapse lib.
    expect(find.text('main.dart'), findsNothing);
    await key(tester, LogicalKeyboardKey.end);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked.last, configFile);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.enter); // Expand lib again.
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('recreated entries preserve expansion and selection by ID', (
    tester,
  ) async {
    final picked = <tree.File>[];
    await pumpTree(tester, entries: entries(), onFilePicked: picked.add);
    await tester.tap(find.text('lib'));
    await tester.pump();
    await tester.tap(find.text('main.dart'));
    await tester.pump();

    const renamed = tree.File(id: 'main', name: 'renamed.dart');
    await pumpTree(
      tester,
      entries: [
        tree.Folder(id: 'lib', name: 'source', children: [renamed]),
        tree.Folder(
          id: 'new',
          name: 'new',
          initiallyExpanded: true,
          children: [configFile],
        ),
      ],
      onFilePicked: picked.add,
    );
    expect(find.text('renamed.dart'), findsOneWidget);
    expect(find.text('pubspec.yaml'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked.last, same(renamed));
  });

  testWidgets('nested expansion survives collapsing a parent', (tester) async {
    await pumpTree(tester, entries: entries(expanded: true));
    await tester.tap(find.text('nested'));
    await tester.pump();
    expect(find.text('part.step'), findsOneWidget);
    await tester.tap(find.text('lib'));
    await tester.pump();
    await tester.tap(find.text('lib'));
    await tester.pump();
    expect(find.text('part.step'), findsOneWidget);
  });

  testWidgets('hidden initial selection falls back to a visible ancestor', (
    tester,
  ) async {
    final picked = <tree.File>[];
    await pumpTree(
      tester,
      entries: entries(),
      selectedId: 'main',
      onFilePicked: picked.add,
    );
    expect(picked, isEmpty);
    await key(tester, LogicalKeyboardKey.enter); // Expands the selected lib.
    expect(find.text('main.dart'), findsOneWidget);
    expect(picked, isEmpty);
  });

  testWidgets('removing the selection leaves keyboard navigation usable', (
    tester,
  ) async {
    final picked = <tree.File>[];
    await pumpTree(
      tester,
      entries: entries(expanded: true),
      selectedId: 'main',
      onFilePicked: picked.add,
    );
    await pumpTree(tester, entries: [configFile], onFilePicked: picked.add);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked, [configFile]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('End scrolls a large tree to the selected file', (tester) async {
    final picked = <tree.File>[];
    await pumpTree(
      tester,
      entries: List.generate(
        100,
        (i) => tree.File(id: '$i', name: 'file_$i.dart'),
      ),
      onFilePicked: picked.add,
      height: 72,
    );
    expect(find.text('file_99.dart'), findsNothing);
    await key(tester, LogicalKeyboardKey.end);
    await tester.pump();
    expect(find.text('file_99.dart'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked.single.id, '99');
    await key(tester, LogicalKeyboardKey.home);
    await tester.pump();
    expect(find.text('file_0.dart'), findsOneWidget);
  });

  testWidgets(
    'color modifiers, custom icons, and long labels work in both themes',
    (tester) async {
      const file = tree.File(
        id: 'long',
        name: 'a_very_long_filename_that_should_be_truncated.dart',
        path: '/project/long.dart',
        colorModifier: Colors.green,
      );
      for (final brightness in Brightness.values) {
        await pumpTree(
          tester,
          entries: [file],
          theme: ThemeData(brightness: brightness),
          width: 120,
        );
        final text = tester.widget<Text>(find.text(file.name));
        expect(text.style?.color, Colors.green);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(tester.widget<Icon>(find.byType(Icon)).color, Colors.green);
        expect(find.byTooltip(file.path!), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await pumpTree(
        tester,
        entries: [file],
        iconBuilder: (context, entry, expanded) => const Icon(Icons.star),
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
    },
  );

  testWidgets('rows expose accessible selection, expansion, and tap actions', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTree(tester, entries: entries(), selectedId: 'lib');
    expect(
      tester.getSemantics(find.bySemanticsLabel('lib')),
      matchesSemantics(
        label: 'lib',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasExpandedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('modified keys pass through to application shortcuts', (
    tester,
  ) async {
    final picked = <tree.File>[];
    await pumpTree(
      tester,
      entries: [mainFile, configFile],
      selectedId: 'main',
      onFilePicked: picked.add,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await key(tester, LogicalKeyboardKey.enter);
    expect(picked, [mainFile]);
  });

  testWidgets('empty trees and empty folders are safe to navigate', (
    tester,
  ) async {
    await pumpTree(tester, entries: []);
    expect(find.text('No files'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await pumpTree(
      tester,
      entries: [tree.Folder(id: 'empty', name: 'empty')],
    );
    await key(tester, LogicalKeyboardKey.home);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate IDs are rejected even across collapsed folders', (
    tester,
  ) async {
    await pumpTree(
      tester,
      entries: [
        mainFile,
        tree.Folder(id: 'lib', name: 'lib', children: [mainFile]),
      ],
    );
    expect(tester.takeException(), isArgumentError);
  });
}
