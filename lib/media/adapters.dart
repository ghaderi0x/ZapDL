import 'dart:convert';

import 'media_models.dart';

/// Parsers in this file are pure functions so they can be tested offline with
/// saved samples. The pages/APIs they read belong to third parties and can
/// change at any time; when they do, only these parsers need updating.

String _unescapeHtml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

String _extFromUrl(String url, String fallback) {
  final path = Uri.tryParse(url)?.path ?? '';
  final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(path);
  return m == null ? fallback : m.group(1)!.toLowerCase();
}

// ------------------------------------------------------------------ Reddit

/// Parses the JSON returned by `<post url>.json`.
MediaInfo parseRedditJson(String body, String pageUrl) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MediaException('parse', 'reddit json');
  }
  Map<String, dynamic>? post;
  if (decoded is List && decoded.isNotEmpty) {
    final children = ((decoded.first as Map)['data'] as Map?)?['children'] as List?;
    if (children != null && children.isNotEmpty) {
      post = ((children.first as Map)['data'] as Map).cast<String, dynamic>();
    }
  }
  if (post == null) throw const MediaException('notFound');

  final title = (post['title'] as String?) ?? 'Reddit post';
  final formats = <MediaFormat>[];
  final secure = (post['secure_media'] as Map?) ?? (post['media'] as Map?);
  final rv = (secure?['reddit_video'] as Map?) ??
      (((post['preview'] as Map?)?['reddit_video_preview']) as Map?);
  if (rv != null && rv['fallback_url'] is String) {
    final video = (rv['fallback_url'] as String).split('?').first;
    final height = rv['height'];
    final hasSound = rv['has_audio'] != false && rv['is_gif'] != true;
    formats.add(MediaFormat(
      id: 'video',
      url: video,
      label: height == null ? 'Video mp4' : '${height}p mp4',
      extension: 'mp4',
      hasAudio: false,
      note: hasSound ? 'videoOnlyNoSound' : null,
    ));
    if (hasSound) {
      // Reddit serves sound as a separate file next to the video.
      final audio = video.replaceFirst(RegExp(r'DASH_\d+\.mp4'), 'DASH_AUDIO_128.mp4');
      if (audio != video) {
        formats.add(MediaFormat(
          id: 'audio',
          url: audio,
          label: 'Audio',
          extension: 'mp4',
          hasVideo: false,
        ));
      }
    }
  }

  final media = post['media_metadata'];
  if (post['is_gallery'] == true && media is Map) {
    var i = 0;
    for (final entry in media.entries) {
      final m = entry.value as Map;
      final s = m['s'] as Map?;
      final u = (s?['u'] ?? s?['gif']) as String?;
      if (u == null) continue;
      i++;
      final url = _unescapeHtml(u);
      formats.add(MediaFormat(
        id: 'img$i',
        url: url,
        label: 'Image $i',
        extension: _extFromUrl(url, 'jpg'),
        hasVideo: false,
        hasAudio: false,
        isImage: true,
      ));
    }
  } else {
    final direct = post['url_overridden_by_dest'] as String?;
    if (direct != null &&
        RegExp(r'^https://(i\.redd\.it|preview\.redd\.it|i\.imgur\.com)/').hasMatch(direct)) {
      final url = _unescapeHtml(direct);
      formats.add(MediaFormat(
        id: 'image',
        url: url,
        label: 'Image',
        extension: _extFromUrl(url, 'jpg'),
        hasVideo: false,
        hasAudio: false,
        isImage: true,
      ));
    }
  }

  if (formats.isEmpty) throw const MediaException('notFound', 'no media in post');
  final thumb = post['thumbnail'] as String?;
  return MediaInfo(
    platform: 'Reddit',
    title: title,
    sourcePage: pageUrl,
    uploader: post['author'] as String?,
    thumbnail: (thumb != null && thumb.startsWith('http')) ? thumb : null,
    formats: formats,
  );
}

// ---------------------------------------------------------------- Telegram

/// Parses the public embed page `https://t.me/<channel>/<id>?embed=1`.
/// Only public channels have such a page.
MediaInfo parseTelegramEmbed(String html, String pageUrl) {
  final formats = <MediaFormat>[];
  var n = 0;
  for (final m in RegExp(r'<video[^>]*\ssrc="([^"]+)"').allMatches(html)) {
    n++;
    final url = _unescapeHtml(m.group(1)!);
    formats.add(MediaFormat(
      id: 'video$n',
      url: url,
      label: n == 1 ? 'Video' : 'Video $n',
      extension: _extFromUrl(url, 'mp4'),
    ));
  }
  n = 0;
  for (final m in RegExp(
    r'tgme_widget_message_photo_wrap[^>]*background-image:url\(\x27([^\x27]+)\x27\)',
  ).allMatches(html)) {
    n++;
    final url = _unescapeHtml(m.group(1)!);
    formats.add(MediaFormat(
      id: 'photo$n',
      url: url,
      label: 'Photo $n',
      extension: _extFromUrl(url, 'jpg'),
      hasVideo: false,
      hasAudio: false,
      isImage: true,
    ));
  }
  if (formats.isEmpty) throw const MediaException('notFound', 'no media in embed');
  final text = RegExp(r'tgme_widget_message_text[^>]*>(.*?)</div>', dotAll: true)
      .firstMatch(html)
      ?.group(1);
  final title = text == null
      ? 'Telegram post'
      : _unescapeHtml(text.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim());
  return MediaInfo(
    platform: 'Telegram',
    title: title.isEmpty ? 'Telegram post' : (title.length > 80 ? title.substring(0, 80) : title),
    sourcePage: pageUrl,
    formats: formats,
  );
}

// ------------------------------------------------------------- OpenGraph

String? _meta(String html, List<String> props) {
  for (final prop in props) {
    final p = RegExp.escape(prop);
    final a = RegExp(
      '<meta[^>]+(?:property|name)=["\']$p["\'][^>]*content=["\']([^"\']*)["\']',
      caseSensitive: false,
    ).firstMatch(html);
    if (a != null) return _unescapeHtml(a.group(1)!);
    final b = RegExp(
      '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$p["\']',
      caseSensitive: false,
    ).firstMatch(html);
    if (b != null) return _unescapeHtml(b.group(1)!);
  }
  return null;
}

/// Generic page reader: Open Graph / Twitter card video tags and `<video>` /
/// `<source>` elements. Resolves relative URLs against [pageUrl].
MediaInfo parseOpenGraph(String html, String pageUrl) {
  final base = Uri.parse(pageUrl);
  String abs(String u) => base.resolve(_unescapeHtml(u)).toString();
  final formats = <MediaFormat>[];
  final seen = <String>{};

  void addVideo(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    final url = abs(raw.trim());
    if (!url.startsWith('http') || !seen.add(url)) return;
    final ext = _extFromUrl(url, 'mp4');
    // Embedded players (html pages) are not files.
    if (const {'html', 'htm', 'php', 'aspx'}.contains(ext)) return;
    formats.add(MediaFormat(
      id: 'v${formats.length + 1}',
      url: url,
      label: 'Video $ext',
      extension: ext,
    ));
  }

  addVideo(_meta(html, ['og:video:secure_url', 'og:video:url', 'og:video']));
  addVideo(_meta(html, ['twitter:player:stream']));
  for (final m in RegExp(r"""<(?:video|source)[^>]*\ssrc=["']([^"']+)["']""", caseSensitive: false)
      .allMatches(html)) {
    addVideo(m.group(1));
  }

  final image = _meta(html, ['og:image:secure_url', 'og:image', 'twitter:image']);
  if (formats.isEmpty && image != null) {
    final url = abs(image);
    formats.add(MediaFormat(
      id: 'image',
      url: url,
      label: 'Image',
      extension: _extFromUrl(url, 'jpg'),
      hasVideo: false,
      hasAudio: false,
      isImage: true,
    ));
  }
  if (formats.isEmpty) throw const MediaException('unsupported');

  final title = _meta(html, ['og:title', 'twitter:title']) ??
      RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
          .firstMatch(html)
          ?.group(1)
          ?.trim() ??
      base.host;
  return MediaInfo(
    platform: base.host,
    title: _unescapeHtml(title),
    sourcePage: pageUrl,
    thumbnail: image == null ? null : abs(image),
    formats: formats,
  );
}

// ------------------------------------------------------------------ yt-dlp

/// Parses `yt-dlp --dump-single-json` output. Only formats that are a single
/// direct HTTP(S) file are offered (no HLS/DASH manifests, which need ffmpeg).
MediaInfo parseYtDlpJson(String body, String pageUrl) {
  final Map<String, dynamic> j;
  try {
    j = (jsonDecode(body) as Map).cast<String, dynamic>();
  } on Object {
    throw const MediaException('parse', 'yt-dlp json');
  }
  final out = <MediaFormat>[];
  final raw = (j['formats'] as List?) ?? const [];
  for (final f in raw.whereType<Map>()) {
    final url = f['url'] as String?;
    final protocol = (f['protocol'] as String?) ?? '';
    if (url == null || (protocol != 'https' && protocol != 'http')) continue;
    final v = (f['vcodec'] as String?) ?? 'none';
    final a = (f['acodec'] as String?) ?? 'none';
    final hasV = v != 'none';
    final hasA = a != 'none';
    if (!hasV && !hasA) continue;
    final ext = (f['ext'] as String?) ?? 'mp4';
    final height = f['height'];
    final size = (f['filesize'] ?? f['filesize_approx']);
    final headers = <String, String>{
      for (final e in ((f['http_headers'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    };
    headers.removeWhere((k, _) => k.toLowerCase() == 'accept-encoding');
    out.add(MediaFormat(
      id: (f['format_id'] ?? '${out.length}').toString(),
      url: url,
      label: hasV ? '${height ?? '?'}p $ext' : 'Audio ${f['abr'] == null ? '' : '${(f['abr'] as num).round()} kbps '}$ext'.trim(),
      extension: ext,
      sizeBytes: size is num ? size.toInt() : null,
      hasVideo: hasV,
      hasAudio: hasA,
      headers: headers,
      note: (hasV && !hasA) ? 'videoOnlyNoSound' : null,
    ));
  }
  if (out.isEmpty) throw const MediaException('notFound', 'no direct formats');
  // Best first: muxed by height, then the rest.
  int h(MediaFormat f) => int.tryParse(RegExp(r'^(\d+)p').firstMatch(f.label)?.group(1) ?? '') ?? 0;
  out.sort((a, b) {
    final am = a.hasVideo && a.hasAudio ? 1 : 0;
    final bm = b.hasVideo && b.hasAudio ? 1 : 0;
    if (am != bm) return bm.compareTo(am);
    return h(b).compareTo(h(a));
  });
  final dur = j['duration'];
  return MediaInfo(
    platform: (j['extractor_key'] as String?) ?? Uri.parse(pageUrl).host,
    title: (j['title'] as String?) ?? pageUrl,
    sourcePage: pageUrl,
    uploader: j['uploader'] as String?,
    thumbnail: j['thumbnail'] as String?,
    duration: dur is num ? Duration(seconds: dur.toInt()) : null,
    formats: out,
  );
}
