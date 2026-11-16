import 'dart:convert';

import 'media_models.dart';

/// Script files referenced by a SoundCloud page (the client id lives in one).
List<String> soundCloudScriptUrls(String html) => [
      for (final m in RegExp(r'<script[^>]+src="(https://[^"]*sndcdn\.com/[^"]+\.js)"').allMatches(html))
        m.group(1)!,
    ];

/// Finds the public web client id inside a SoundCloud script, or null.
String? soundCloudClientId(String js) {
  final m = RegExp(r'client_id\s*[:=]\s*"([A-Za-z0-9]{20,40})"').firstMatch(js);
  return m?.group(1);
}

/// A transcoding the player offers: [url] still has to be asked for the real
/// stream address.
class SoundCloudTranscoding {
  const SoundCloudTranscoding(this.url, this.preset, this.mime);
  final String url;
  final String preset;
  final String mime;
}

class SoundCloudTrack {
  const SoundCloudTrack({
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.duration,
    required this.trackAuthorization,
    required this.transcodings,
  });
  final String title;
  final String? uploader;
  final String? thumbnail;
  final Duration? duration;
  final String? trackAuthorization;

  /// Progressive (plain file) transcodings only; HLS streams are not used.
  final List<SoundCloudTranscoding> transcodings;
}

/// Parses the `api-v2 /resolve` answer for one track.
SoundCloudTrack parseSoundCloudTrack(String body) {
  final dynamic root;
  try {
    root = jsonDecode(body);
  } catch (_) {
    throw const MediaException('parse');
  }
  if (root is! Map) throw const MediaException('parse');
  if (root['kind'] != 'track') throw const MediaException('unsupported');
  final media = root['media'];
  final list = media is Map ? media['transcodings'] : null;
  final out = <SoundCloudTranscoding>[];
  if (list is List) {
    for (final t in list) {
      if (t is! Map) continue;
      final fmt = t['format'];
      if (fmt is Map && fmt['protocol'] == 'progressive' && t['url'] is String) {
        out.add(SoundCloudTranscoding(
          t['url'] as String,
          (t['preset'] ?? '') as String,
          (fmt['mime_type'] ?? 'audio/mpeg') as String,
        ));
      }
    }
  }
  if (out.isEmpty) {
    // Snipped previews and protected tracks have no full progressive file.
    throw MediaException(root['policy'] == 'SNIP' ? 'loginRequired' : 'notFound');
  }
  final user = root['user'];
  final ms = root['full_duration'] ?? root['duration'];
  final art = root['artwork_url'] ?? (user is Map ? user['avatar_url'] : null);
  return SoundCloudTrack(
    title: (root['title'] as String?)?.trim().isNotEmpty == true ? root['title'] as String : 'SoundCloud',
    uploader: user is Map ? user['username'] as String? : null,
    thumbnail: art is String ? art.replaceFirst('-large.', '-t500x500.') : null,
    duration: ms is int ? Duration(milliseconds: ms) : null,
    trackAuthorization: root['track_authorization'] as String?,
    transcodings: out,
  );
}

/// Reads the `{"url": "..."}` answer of a transcoding request.
String parseSoundCloudStreamUrl(String body) {
  try {
    final j = jsonDecode(body);
    if (j is Map && j['url'] is String) return j['url'] as String;
  } catch (_) {}
  throw const MediaException('parse');
}

MediaInfo soundCloudInfo(SoundCloudTrack t, String streamUrl, String pageUrl, String mime) {
  final ext = mime.contains('ogg')
      ? 'ogg'
      : mime.contains('mp4') || mime.contains('aac')
          ? 'm4a'
          : 'mp3';
  return MediaInfo(
    platform: 'SoundCloud',
    title: t.title,
    sourcePage: pageUrl,
    uploader: t.uploader,
    thumbnail: t.thumbnail,
    duration: t.duration,
    formats: [
      MediaFormat(
        id: 'audio',
        url: streamUrl,
        label: ext.toUpperCase(),
        extension: ext,
        hasVideo: false,
      ),
    ],
  );
}
