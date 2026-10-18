import 'file_tree_entry.dart';
import 'file_type.dart';

/// Immutable file metadata. Import this module with a prefix when also using
/// `dart:io`, which has its own `File` and `FileSystemEntity` types.
class File extends FileTreeEntry {
  const File({
    required super.id,
    required super.name,
    super.path,
    super.colorModifier,
    this._type,
  });

  final FileType? _type;

  /// An explicit type takes precedence over inference from the filename.
  FileType get type => _type ?? FileType.fromName(name);
}
