/// Detects multi-part file names (game archives, split RARs) and builds the
/// URL of the next part: `game.part1.rar` -> `game.part2.rar`,
/// `data.001` -> `data.002`, `vol01.zip` -> `vol02.zip`.
library;

final _partWord = RegExp(
  r'((?:part|pt|vol|disk|disc|cd)[\s._-]?)(\d+)',
  caseSensitive: false,
);
final _numericExt = RegExp(r'\.(\d{2,4})$');
final _zipSplit = RegExp(r'\.z(\d{2})$', caseSensitive: false);

String _increment(String digits, int by) {
  final n = int.parse(digits) + by;
  return n.toString().padLeft(digits.length, '0');
}

/// The path segment is changed; query and fragment are kept as they were.
String? nextPartUrl(String url, {int by = 1}) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final segments = List<String>.of(uri.pathSegments);
  final last = Uri.decodeComponent(segments.last);

  String? changed;
  // Prefer the last "partN" in the name, so "game2.part3.rar" bumps 3, not 2.
  final words = _partWord.allMatches(last).toList();
  if (words.isNotEmpty) {
    final m = words.last;
    changed = last.replaceRange(m.start, m.end, '${m.group(1)}${_increment(m.group(2)!, by)}');
  } else if (_numericExt.hasMatch(last)) {
    changed = last.replaceFirstMapped(_numericExt, (m) => '.${_increment(m.group(1)!, by)}');
  } else if (_zipSplit.hasMatch(last)) {
    changed = last.replaceFirstMapped(_zipSplit, (m) => '.z${_increment(m.group(1)!, by)}');
  }
  if (changed == null) return null;
  segments[segments.length - 1] = changed;
  return uri.replace(pathSegments: segments).toString();
}

/// True when [url] looks like one part of a multi-part file.
bool looksLikePart(String url) => nextPartUrl(url) != null;
