import 'dart:convert';

import 'media_models.dart';

/// Pure parsers for TikTok, X/Twitter, Instagram and YouTube's InnerTube API.
/// Like adapters.dart they take text in and return [MediaInfo], so they can be
/// tested offline. The services behind them are third parties that change
/// without notice; see docs/MEDIA_SOURCES.md for what each one relies on.

String _unescapeJsonString(String raw) {
  try {
    return jsonDecode('"$raw"') as String;
  } catch (_) {
    return raw.replaceAll(r'\/', '/').replaceAll(r'&', '&');
  }
}

String _ext(String url, String fallback) {
  final path = Uri.tryParse(url)?.path ?? '';
  final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(path);
  return m == null ? fallback : m.group(1)!.toLowerCase();
}

String _shorten(String s, [int max = 80]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > max ? t.substring(0, max) : t;
}

Map<String, dynamic>? _asMap(Object? o) => o is Map ? o.cast<String, dynamic>() : null;

// ------------------------------------------------------------------ TikTok

/// Parses the JSON of `https://www.tikwm.com/api/?url=<tiktok link>&hd=1`.
MediaInfo parseTikWm(String body, String pageUrl, {String host = 'https://www.tikwm.com'}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MediaException('parse', 'tiktok json');
  }
  final root = _asMap(decoded);
  final data = _asMap(root?['data']);
  if (root == null || data == null || (root['code'] is num && root['code'] != 0)) {
    throw const MediaException('notFound', 'tiktok');
  }
  String abs(String u) => u.startsWith('http') ? u : '$host${u.startsWith('/') ? '' : '/'}$u';

  final formats = <MediaFormat>[];
  void addVideo(String id, Object? u, String label) {
    if (u is String && u.isNotEmpty) {
      final url = abs(u);
      formats.add(MediaFormat(id: id, url: url, label: label, extension: 'mp4'));
    }
  }

  addVideo('hd', data['hdplay'], 'HD, no watermark');
  addVideo('sd', data['play'], 'No watermark');
  addVideo('wm', data['wmplay'], 'With watermark');
  final music = data['music'];
  if (music is String && music.isNotEmpty) {
    formats.add(MediaFormat(
      id: 'music',
      url: abs(music),
      label: 'Sound (mp3)',
      extension: 'mp3',
      hasVideo: false,
    ));
  }
  final images = data['images'];
  if (images is List) {
    var n = 0;
    for (final img in images.whereType<String>()) {
      n++;
      formats.add(MediaFormat(
        id: 'img$n',
        url: img,
        label: 'Photo $n',
        extension: _ext(img, 'jpg'),
        hasVideo: false,
        hasAudio: false,
        isImage: true,
      ));
    }
  }
  if (formats.isEmpty) throw const MediaException('notFound', 'tiktok no media');
  final author = _asMap(data['author']);
  final seconds = data['duration'];
  return MediaInfo(
    platform: 'TikTok',
    title: _shorten((data['title'] as String?) ?? '').isEmpty
        ? 'TikTok video'
        : _shorten(data['title'] as String),
    sourcePage: pageUrl,
    uploader: (author?['nickname'] ?? author?['unique_id']) as String?,
    thumbnail: data['cover'] as String?,
    duration: seconds is num ? Duration(seconds: seconds.toInt()) : null,
    formats: formats,
  );
}

// --------------------------------------------------------------- X / Twitter

/// Parses the JSON of `https://api.fxtwitter.com/status/<id>` (FxTwitter).
MediaInfo parseFxTwitter(String body, String pageUrl) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MediaException('parse', 'x json');
  }
  final root = _asMap(decoded);
  final tweet = _asMap(root?['tweet']);
  if (tweet == null) throw const MediaException('notFound', 'x');
  final media = _asMap(tweet['media']);
  final formats = <MediaFormat>[];

  final videos = media?['videos'];
  if (videos is List) {
    var n = 0;
    for (final v in videos) {
      final m = _asMap(v);
      final url = m?['url'];
      if (m == null || url is! String) continue;
      n++;
      final h = m['height'];
      final gif = m['type'] == 'gif';
      formats.add(MediaFormat(
        id: 'video$n',
        url: url,
        label: '${gif ? 'GIF' : 'Video'}${videos.length > 1 ? ' $n' : ''}${h is num ? ' ${h.toInt()}p' : ''}',
        extension: _ext(url, 'mp4'),
        hasAudio: !gif,
      ));
    }
  }
  final photos = media?['photos'];
  if (photos is List) {
    var n = 0;
    for (final ph in photos) {
      final url = _asMap(ph)?['url'];
      if (url is! String) continue;
      n++;
      formats.add(MediaFormat(
        id: 'photo$n',
        url: url,
        label: 'Photo $n',
        extension: _ext(url, 'jpg'),
        hasVideo: false,
        hasAudio: false,
        isImage: true,
      ));
    }
  }
  if (formats.isEmpty) throw const MediaException('notFound', 'x no media');
  final author = _asMap(tweet['author']);
  final text = (tweet['text'] as String?) ?? '';
  return MediaInfo(
    platform: 'X',
    title: text.trim().isEmpty ? 'X post' : _shorten(text),
    sourcePage: pageUrl,
    uploader: author?['name'] as String?,
    formats: formats,
  );
}

// --------------------------------------------------------------- Instagram

/// Parses the public embed page `https://www.instagram.com/<p|reel|tv>/<code>/embed/captioned/`.
///
/// A reel or video whose file cannot be found raises `loginRequired` instead of
/// quietly offering the cover picture as if it were the video.
MediaInfo parseInstagramEmbed(String html, String pageUrl, {required bool expectsVideo}) {
  final formats = <MediaFormat>[];
  final seen = <String>{};

  for (final m in RegExp(r'"video_url"\s*:\s*"((?:[^"\\]|\\.)*)"').allMatches(html)) {
    final url = _unescapeJsonString(m.group(1)!);
    if (url.startsWith('http') && seen.add(url)) {
      formats.add(MediaFormat(
        id: 'video${formats.length + 1}',
        url: url,
        label: 'Video',
        extension: _ext(url, 'mp4'),
      ));
    }
  }
  for (final m in RegExp(r'<video[^>]*\ssrc="([^"]+)"').allMatches(html)) {
    final url = m.group(1)!.replaceAll('&amp;', '&');
    if (url.startsWith('http') && seen.add(url)) {
      formats.add(MediaFormat(
        id: 'video${formats.length + 1}',
        url: url,
        label: 'Video',
        extension: _ext(url, 'mp4'),
      ));
    }
  }
  final hasVideo = formats.isNotEmpty;

  if (!hasVideo && expectsVideo) {
    throw const MediaException('loginRequired', 'instagram video not public');
  }
  if (!hasVideo) {
    var n = 0;
    for (final m in RegExp(r'"display_url"\s*:\s*"((?:[^"\\]|\\.)*)"').allMatches(html)) {
      final url = _unescapeJsonString(m.group(1)!);
      if (url.startsWith('http') && seen.add(url)) {
        n++;
        formats.add(MediaFormat(
          id: 'photo$n',
          url: url,
          label: 'Photo $n',
          extension: _ext(url, 'jpg'),
          hasVideo: false,
          hasAudio: false,
          isImage: true,
        ));
      }
    }
  }
  if (formats.isEmpty) throw const MediaException('loginRequired', 'instagram empty');

  final user = RegExp(r'"username"\s*:\s*"([^"]+)"').firstMatch(html)?.group(1);
  return MediaInfo(
    platform: 'Instagram',
    title: user == null ? 'Instagram post' : 'Instagram · $user',
    sourcePage: pageUrl,
    uploader: user,
    formats: formats,
  );
}

// ------------------------------------------------------- YouTube (InnerTube)

/// Headers the ANDROID_VR client uses; stream links it returns need no
/// signature, and are fetched with the same user agent.
const innerTubeUserAgent =
    'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip';

Map<String, dynamic> innerTubePlayerRequest(String videoId) => {
      'context': {
        'client': {
          'clientName': 'ANDROID_VR',
          'clientVersion': '1.60.19',
          'deviceMake': 'Oculus',
          'deviceModel': 'Quest 3',
          'androidSdkVersion': 32,
          'osName': 'Android',
          'osVersion': '12L',
          'hl': 'en',
          'gl': 'US',
        },
      },
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };

/// Extracts the 11-character video id from any YouTube link form.
String? youtubeVideoId(Uri u) {
  final h = u.host.toLowerCase();
  String? candidate;
  if (h == 'youtu.be') {
    candidate = u.pathSegments.isEmpty ? null : u.pathSegments.first;
  } else if (u.queryParameters['v'] != null) {
    candidate = u.queryParameters['v'];
  } else if (u.pathSegments.length >= 2 &&
      const {'shorts', 'live', 'embed', 'v'}.contains(u.pathSegments.first)) {
    candidate = u.pathSegments[1];
  }
  if (candidate != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate)) return candidate;
  return null;
}

/// Parses the response of `youtubei/v1/player`. Only streams with a plain URL
/// are offered (ciphered ones would need the JS player).
MediaInfo parseInnerTubePlayer(String body, String pageUrl) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const MediaException('parse', 'innertube json');
  }
  final root = _asMap(decoded);
  if (root == null) throw const MediaException('parse', 'innertube');
  final status = _asMap(root['playabilityStatus']);
  final st = status?['status'];
  if (st != 'OK') {
    final reason = '${status?['reason'] ?? ''}'.toLowerCase();
    if (st == 'LOGIN_REQUIRED') {
      throw MediaException(
          reason.contains('bot') ? 'blocked' : 'loginRequired', status?['reason'] as String?);
    }
    throw MediaException('notFound', status?['reason'] as String?);
  }
  final details = _asMap(root['videoDetails']);
  final streaming = _asMap(root['streamingData']);
  final formats = <MediaFormat>[];

  final muxed = (streaming?['formats'] as List?) ?? const [];
  final muxedParsed = <(int, MediaFormat)>[];
  for (final f in muxed) {
    final m = _asMap(f);
    final url = m?['url'];
    if (m == null || url is! String) continue;
    final height = (m['height'] as num?)?.toInt() ?? 0;
    final mime = (m['mimeType'] as String?) ?? 'video/mp4';
    final container = mime.split(';').first.split('/').last;
    muxedParsed.add((
      height,
      MediaFormat(
        id: 'm${m['itag']}',
        url: url,
        label: '${height}p $container',
        extension: container,
        sizeBytes: int.tryParse('${m['contentLength'] ?? ''}'),
        headers: const {'User-Agent': innerTubeUserAgent},
      ),
    ));
  }
  muxedParsed.sort((a, b) => b.$1.compareTo(a.$1));
  formats.addAll(muxedParsed.map((e) => e.$2));

  final adaptive = (streaming?['adaptiveFormats'] as List?) ?? const [];
  final audio = <(int, MediaFormat)>[];
  for (final f in adaptive) {
    final m = _asMap(f);
    final url = m?['url'];
    final mime = (m?['mimeType'] as String?) ?? '';
    if (m == null || url is! String || !mime.startsWith('audio/')) continue;
    final container = mime.split(';').first.split('/').last;
    final bitrate = ((m['bitrate'] as num?) ?? 0).toInt();
    audio.add((
      bitrate,
      MediaFormat(
        id: 'a${m['itag']}',
        url: url,
        label: 'Audio ${(bitrate / 1000).round()} kbps $container',
        extension: container == 'mp4' ? 'm4a' : container,
        sizeBytes: int.tryParse('${m['contentLength'] ?? ''}'),
        hasVideo: false,
        headers: const {'User-Agent': innerTubeUserAgent},
      ),
    ));
  }
  audio.sort((a, b) => b.$1.compareTo(a.$1));
  formats.addAll(audio.map((e) => e.$2));

  if (formats.isEmpty) throw const MediaException('blocked', 'no direct streams');
  final secs = int.tryParse('${details?['lengthSeconds'] ?? ''}');
  final thumbs = (_asMap(details?['thumbnail'])?['thumbnails'] as List?) ?? const [];
  return MediaInfo(
    platform: 'YouTube',
    title: (details?['title'] as String?) ?? 'YouTube video',
    sourcePage: pageUrl,
    uploader: details?['author'] as String?,
    thumbnail: thumbs.isEmpty ? null : _asMap(thumbs.last)?['url'] as String?,
    duration: secs == null ? null : Duration(seconds: secs),
    formats: formats,
  );
}
