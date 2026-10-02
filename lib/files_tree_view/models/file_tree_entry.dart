import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A virtual or on-disk entry. IDs must be unique across the whole tree and
/// stable between rebuilds; names and paths can change without losing UI state.
@immutable
abstract class FileTreeEntry {
  const FileTreeEntry({
    required this.id,
    required this.name,
    this.path,
    this.colorModifier,
  }) : assert(id != ''),
       assert(name != '');

  final String id;
  final String name;

  /// Optional full path, also shown in the row's tooltip.
  final String? path;

  /// Overrides label and icon colors, for example for a Git status.
  /// This is presentation metadata; entries do not depend on Git or disk IO.
  final Color? colorModifier;
}
