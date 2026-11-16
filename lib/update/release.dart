import 'dart:convert';

import 'semver.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });

  final String name;

  /// browser_download_url
  final String url;
  final int size;

  /// From GitHub's `digest` field ("sha256:<hex>") when present.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.name,
    required this.notes,
    required this.pageUrl,
    required this.prerelease,
    required this.assets,
    this.publishedAt,
  });

  final String tag;
  final SemVer version;
  final String name;

  /// Release notes (Markdown), shown as plain text.
  final String notes;
  final String pageUrl;
  final bool prerelease;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// Parses one GitHub release object. Returns null for drafts or tags that
  /// are not semantic versions, so odd tags can never trigger an "update".
  static ReleaseInfo? fromJson(Map<String, dynamic> j) {
    if (j['draft'] == true) return null;
    final tag = j['tag_name'] as String?;
    final v = tag == null ? null : SemVer.tryParse(tag);
    if (tag == null || v == null) return null;
    final assets = <ReleaseAsset>[];
    for (final a in (j['assets'] as List? ?? const []).whereType<Map>()) {
      final name = a['name'] as String?;
      final url = a['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      final digest = a['digest'] as String?;
      assets.add(ReleaseAsset(
        name: name,
        url: url,
        size: (a['size'] as num? ?? 0).toInt(),
        sha256: (digest != null && digest.startsWith('sha256:'))
            ? digest.substring(7).toLowerCase()
            : null,
      ));
    }
    return ReleaseInfo(
      tag: tag,
      version: v,
      name: (j['name'] as String?)?.trim().isNotEmpty == true ? j['name'] as String : tag,
      notes: (j['body'] as String?) ?? '',
      pageUrl: (j['html_url'] as String?) ?? '',
      prerelease: j['prerelease'] == true || v.isPrerelease,
      publishedAt: DateTime.tryParse((j['published_at'] as String?) ?? ''),
      assets: assets,
    );
  }

  /// Picks the newest release from a decoded GitHub response: either one
  /// release object (`/releases/latest`) or a list (`/releases`).
  static ReleaseInfo? newestFrom(Object? decoded, {required bool includePrereleases}) {
    final items = decoded is List ? decoded : [decoded];
    ReleaseInfo? best;
    for (final item in items.whereType<Map>()) {
      final r = fromJson(item.cast<String, dynamic>());
      if (r == null) continue;
      if (r.prerelease && !includePrereleases) continue;
      if (best == null || r.version > best.version) best = r;
    }
    return best;
  }

  static ReleaseInfo? parse(String body, {required bool includePrereleases}) {
    try {
      return newestFrom(jsonDecode(body), includePrereleases: includePrereleases);
    } on FormatException {
      return null;
    }
  }
}

/// Reads a `SHA256SUMS` style file (`<hex>  <name>` per line, `*` before the
/// name for binary mode) into a name -> hex map.
Map<String, String> parseChecksumFile(String text) {
  final out = <String, String>{};
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line.trim());
    if (m != null) out[m.group(2)!] = m.group(1)!.toLowerCase();
  }
  return out;
}
