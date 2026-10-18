/// Semantic types used by the default icon mapping. Callers can override a
/// file's inferred type and provide their own icon builder in FilesTreeView.
enum FileType {
  unknown,
  dart,
  code,
  json,
  yaml,
  markdown,
  text,
  image,
  archive,
  cad;

  static FileType fromName(String name) {
    final lower = name.toLowerCase();
    if (const {
      'license',
      'readme',
      '.gitignore',
      '.gitattributes',
    }.contains(lower)) {
      return text;
    }
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return unknown;
    return switch (lower.substring(dot + 1)) {
      'dart' => dart,
      'json' || 'jsonc' => json,
      'yaml' || 'yml' || 'toml' || 'ini' || 'xml' => yaml,
      'md' || 'markdown' => markdown,
      'txt' || 'log' || 'csv' => text,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' || 'bmp' => image,
      'zip' || 'gz' || 'tar' || '7z' || 'rar' => archive,
      'step' || 'stp' || 'stl' || 'obj' || 'dxf' || 'iges' || 'igs' => cad,
      'js' ||
      'jsx' ||
      'ts' ||
      'tsx' ||
      'py' ||
      'c' ||
      'h' ||
      'cpp' ||
      'hpp' ||
      'rs' ||
      'go' ||
      'java' ||
      'kt' ||
      'swift' ||
      'sh' ||
      'html' ||
      'css' => code,
      _ => unknown,
    };
  }
}
