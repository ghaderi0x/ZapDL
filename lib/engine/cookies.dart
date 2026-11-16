import 'errors.dart';
import 'models.dart';

/// One line of a Netscape/curl `cookies.txt` file.
class NetscapeCookie {
  const NetscapeCookie({
    required this.domain,
    required this.includeSubdomains,
    required this.path,
    required this.secure,
    required this.expires,
    required this.name,
    required this.value,
  });

  final String domain;
  final bool includeSubdomains;
  final String path;
  final bool secure;

  /// null = session cookie.
  final DateTime? expires;
  final String name;
  final String value;
}

List<NetscapeCookie> parseNetscapeCookies(String text) {
  final out = <NetscapeCookie>[];
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#HttpOnly_')) {
      line = line.substring('#HttpOnly_'.length);
    } else if (line.startsWith('#')) {
      continue;
    }
    var f = line.split('\t');
    if (f.length < 7) f = line.split(RegExp(r'\s+'));
    if (f.length < 7) continue;
    final exp = int.tryParse(f[4]) ?? 0;
    out.add(NetscapeCookie(
      domain: f[0].toLowerCase(),
      includeSubdomains: f[1].toUpperCase() == 'TRUE',
      path: f[2].isEmpty ? '/' : f[2],
      secure: f[3].toUpperCase() == 'TRUE',
      expires: exp <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      name: f[5],
      value: f.sublist(6).join(' '),
    ));
  }
  return out;
}

bool _domainMatches(NetscapeCookie c, String host) {
  host = host.toLowerCase();
  final bare = c.domain.startsWith('.') ? c.domain.substring(1) : c.domain;
  if (host == bare) return true;
  final subdomains = c.includeSubdomains || c.domain.startsWith('.');
  return subdomains && host.endsWith('.$bare');
}

bool _pathMatches(String cookiePath, String requestPath) {
  final rp = requestPath.isEmpty ? '/' : requestPath;
  if (cookiePath == '/' || rp == cookiePath) return true;
  final prefix = cookiePath.endsWith('/') ? cookiePath : '$cookiePath/';
  return rp.startsWith(prefix);
}

/// Builds a `Cookie` header value for [uri] from [cookies], honoring domain,
/// path, Secure and expiry. Returns null when nothing applies.
String? cookieHeaderFor(Uri uri, List<NetscapeCookie> cookies, {DateTime? now}) {
  final t = (now ?? DateTime.now()).toUtc();
  final parts = <String>[];
  for (final c in cookies) {
    if (c.expires != null && !c.expires!.isAfter(t)) continue;
    if (c.secure && uri.scheme != 'https') continue;
    if (!_domainMatches(c, uri.host)) continue;
    if (!_pathMatches(c.path, uri.path)) continue;
    parts.add('${c.name}=${c.value}');
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Accepts either a cookies.txt export or a raw `name=value; name2=value2`
/// string (optionally prefixed with `Cookie:`) and returns the header value
/// for [uri]. Returns null when the input is blank or no cookie applies.
String? cookieHeaderFromInput(String input, Uri uri, {DateTime? now}) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final looksLikeFile = text.contains('\t') || text.startsWith('# Netscape');
  if (looksLikeFile) {
    return cookieHeaderFor(uri, parseNetscapeCookies(text), now: now);
  }
  var raw = text.replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '');
  if (raw.contains(RegExp(r'[\r\n\x00]'))) {
    throw const DownloadFailure(DownloadErrorCode.invalidHeader, detail: 'cookie');
  }
  raw = raw.trim();
  return raw.isEmpty ? null : raw;
}
