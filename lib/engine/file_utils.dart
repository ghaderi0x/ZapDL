import 'dart:io';

import 'package:path/path.dart' as p;

const _reservedWindowsNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Makes an untrusted (server- or user-supplied) name safe to use as a single
/// path component. Prevents path traversal and invalid characters on all
/// supported platforms.
String sanitizeFileName(String input) {
  var name = input.trim();
  final slash = name.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '_');
  name = name.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  if (name.isEmpty) name = 'download';
  final base = name.split('.').first.toUpperCase();
  if (_reservedWindowsNames.contains(base)) name = '_$name';
  if (name.length > 200) {
    final ext = p.extension(name);
    final keepExt = ext.length <= 20 ? ext : '';
    name = name.substring(0, 200 - keepExt.length) + keepExt;
  }
  return name;
}

/// Returns a path in [dir] for [name] that does not exist yet:
/// "file.zip", "file (1).zip", "file (2).zip", ...
String uniquePath(String dir, String name) {
  var candidate = p.join(dir, name);
  if (!_exists(candidate)) return candidate;
  final ext = p.extension(name);
  final stem = p.basenameWithoutExtension(name);
  for (var i = 1; i < 10000; i++) {
    candidate = p.join(dir, '$stem ($i)$ext');
    if (!_exists(candidate)) return candidate;
  }
  return p.join(dir, '$stem (${DateTime.now().millisecondsSinceEpoch})$ext');
}

bool _exists(String path) =>
    FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

/// Guard against a computed path escaping its directory.
bool isInside(String dir, String path) => p.isWithin(dir, path);
