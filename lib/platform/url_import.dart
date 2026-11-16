import 'dart:convert';
import 'dart:io';

import '../engine/probe.dart' show looksLikeDownloadUrl;

/// Finds http(s) URLs in free text (shared text, a pasted list, a .txt file).
/// Trailing punctuation that is almost never part of a URL is trimmed.
List<String> extractUrls(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final m in RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false).allMatches(text)) {
    var u = m.group(0)!;
    while (u.isNotEmpty && '.,;:!?)]}'.contains(u[u.length - 1])) {
      // Keep a closing parenthesis that balances one inside the URL.
      if (u.endsWith(')') && u.split('(').length >= u.split(')').length) break;
      u = u.substring(0, u.length - 1);
    }
    if (looksLikeDownloadUrl(u) && seen.add(u)) out.add(u);
  }
  return out;
}

/// Windows `.url` internet shortcut: `[InternetShortcut]\nURL=...`.
String? parseInternetShortcut(String text) {
  final m = RegExp(r'^\s*URL\s*=\s*(\S+)\s*$', multiLine: true, caseSensitive: false)
      .firstMatch(text);
  final u = m?.group(1);
  return (u != null && looksLikeDownloadUrl(u)) ? u : null;
}

/// macOS `.webloc` property list: `<key>URL</key><string>...</string>`.
String? parseWebloc(String text) {
  final m = RegExp(r'<key>URL</key>\s*<string>([^<]+)</string>').firstMatch(text);
  final u = m?.group(1)?.trim().replaceAll('&amp;', '&');
  return (u != null && looksLikeDownloadUrl(u)) ? u : null;
}

/// Reads URLs from a dropped file. Supports .url, .webloc and any text file
/// (one URL per line or mixed text). Binary or huge files yield nothing.
Future<List<String>> urlsFromFile(String path, {int maxBytes = 1024 * 1024}) async {
  try {
    final file = File(path);
    if (await file.length() > maxBytes) return const [];
    final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    final lower = path.toLowerCase();
    if (lower.endsWith('.url')) {
      final u = parseInternetShortcut(text);
      return u == null ? const [] : [u];
    }
    if (lower.endsWith('.webloc')) {
      final u = parseWebloc(text);
      return u == null ? const [] : [u];
    }
    return extractUrls(text);
  } catch (_) {
    return const [];
  }
}
