import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../engine/filter_bypass.dart';
import '../engine/http_support.dart';
import '../engine/models.dart';
import 'adapters.dart';
import 'media_http.dart';
import 'soundcloud.dart';
import 'media_models.dart';
import 'social.dart';

/// Turns a web-page URL into downloadable [MediaFormat]s.
///
/// Order: yt-dlp (desktop, when installed) for sites it supports, then the
/// built-in adapters (YouTube, Reddit, Telegram), then generic Open Graph.
/// Everything here talks to third-party sites whose markup/APIs change; see
/// docs/MEDIA_SOURCES.md. Users are responsible for respecting each site's
/// terms and the copyright of what they download.
class MediaResolver {
  MediaResolver({this.proxy = const ProxyConfig(), this.ytDlpPath});

  ProxyConfig proxy;

  /// Path of a yt-dlp executable. When null, "yt-dlp" on PATH is tried on desktop.
  String? ytDlpPath;

  static bool get _desktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool isYouTube(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'youtu.be' ||
        h == 'youtube.com' ||
        h.endsWith('.youtube.com') ||
        h == 'youtube-nocookie.com';
  }

  static bool isReddit(Uri u) {
    final h = u.host.toLowerCase();
    return (h == 'reddit.com' || h.endsWith('.reddit.com') || h == 'redd.it') &&
        u.pathSegments.isNotEmpty;
  }

  static bool isTelegram(Uri u) {
    final h = u.host.toLowerCase();
    return (h == 't.me' || h == 'telegram.me') && u.pathSegments.length >= 2;
  }

  static bool isTikTok(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'tiktok.com' || h.endsWith('.tiktok.com');
  }

  static bool isTwitter(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'x.com' ||
        h == 'twitter.com' ||
        h.endsWith('.twitter.com') ||
        h.endsWith('.x.com') ||
        h == 'fxtwitter.com' ||
        h == 'vxtwitter.com';
  }

  static bool isInstagram(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'instagram.com' || h.endsWith('.instagram.com') || h == 'instagr.am';
  }

  static bool isSoundCloud(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'soundcloud.com' || h.endsWith('.soundcloud.com') || h == 'snd.sc';
  }

  static bool isSpotify(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'spotify.com' || h.endsWith('.spotify.com') || h == 'spotify.link';
  }

  /// Sites with a dedicated adapter: when one of them fails, the error is shown
  /// instead of falling back to treating the link as a plain file.
  static bool isKnownPlatform(Uri u) =>
      isYouTube(u) ||
      isReddit(u) ||
      isTelegram(u) ||
      isTikTok(u) ||
      isTwitter(u) ||
      isInstagram(u) ||
      isSoundCloud(u) ||
      isSpotify(u);

  /// True for URLs that are a page to extract from rather than a direct file.
  static bool looksLikePage(Uri u) {
    if (isKnownPlatform(u)) return true;
    final last = u.pathSegments.isEmpty ? '' : u.pathSegments.last;
    final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(last);
    if (m == null) return true; // no extension: probably a page
    return const {'html', 'htm', 'php', 'aspx', 'jsp'}.contains(m.group(1)!.toLowerCase());
  }

  Future<MediaInfo> resolve(String input) async {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const MediaException('unsupported');
    }
    // Nothing may spin forever: filtered networks often just stall.
    try {
      return await _resolve(uri).timeout(
        const Duration(seconds: 100),
        onTimeout: () => throw const MediaException('network', 'timeout'),
      );
    } on MediaException {
      rethrow;
    } catch (e) {
      // Any unexpected failure (TLS, parsing...) must end the spinner too.
      throw MediaException('network', e.toString());
    }
  }

  Future<MediaInfo> _resolve(Uri uri) async {
    final url = uri.toString();

    // Spotify streams are encrypted (DRM); no honest tool can save them.
    if (isSpotify(uri)) throw const MediaException('drm');

    // yt-dlp, when installed, is the most reliable source on desktop.
    if (_desktop) {
      final viaYtDlp = await _tryYtDlp(url);
      if (viaYtDlp != null) return viaYtDlp;
    }

    if (isYouTube(uri)) return _youtube(uri);
    if (isReddit(uri)) return _reddit(uri);
    if (isTelegram(uri)) return _telegram(uri);
    if (isTikTok(uri)) return _tiktok(uri);
    if (isTwitter(uri)) return _twitter(uri);
    if (isInstagram(uri)) return _instagram(uri);
    if (isSoundCloud(uri)) return _soundCloud(uri);

    final html = await fetchText(uri, proxy: proxy, headers: const {
      'Accept': 'text/html,application/xhtml+xml',
    });
    return parseOpenGraph(html, url);
  }

  // ------------------------------------------------- TikTok / X / Instagram

  Future<MediaInfo> _tiktok(Uri uri) async {
    final api = Uri.https('www.tikwm.com', '/api/', {'url': uri.toString(), 'hd': '1'});
    final body = await fetchText(api, proxy: proxy, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    });
    return parseTikWm(body, uri.toString());
  }

  Future<MediaInfo> _twitter(Uri uri) async {
    final id = RegExp(r'/status(?:es)?/(\d+)').firstMatch(uri.path)?.group(1);
    if (id == null) throw const MediaException('unsupported');
    final api = Uri.https('api.fxtwitter.com', '/status/$id');
    final body = await fetchText(api, proxy: proxy, headers: const {'Accept': 'application/json'});
    return parseFxTwitter(body, uri.toString());
  }

  String? _scClientId;

  /// SoundCloud's web player uses a public client id that is embedded in its
  /// scripts. It is looked up once and cached; the lookup repeats if it stops
  /// working.
  Future<String> _soundCloudClientId({bool refresh = false}) async {
    if (!refresh && _scClientId != null) return _scClientId!;
    final home = await fetchText(Uri.https('soundcloud.com', '/'), proxy: proxy, headers: const {
      'Accept': 'text/html',
    });
    final scripts = soundCloudScriptUrls(home).reversed.take(6);
    for (final s in scripts) {
      try {
        final js = await fetchText(Uri.parse(s), proxy: proxy, maxBytes: 8 * 1024 * 1024);
        final id = soundCloudClientId(js);
        if (id != null) return _scClientId = id;
      } on MediaException {
        continue;
      }
    }
    throw const MediaException('parse', 'soundcloud client id');
  }

  Future<MediaInfo> _soundCloud(Uri uri) async {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.host.toLowerCase() != 'on.soundcloud.com' && uri.host != 'snd.sc') {
      if (segs.length < 2 || segs[1] == 'sets' || segs.length > 2 && segs[2] == 'sets') {
        throw const MediaException('unsupported');
      }
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = await _soundCloudClientId(refresh: attempt > 0);
      try {
        final body = await fetchText(
          Uri.https('api-v2.soundcloud.com', '/resolve', {'url': uri.toString(), 'client_id': id}),
          proxy: proxy,
          headers: const {'Accept': 'application/json'},
        );
        final track = parseSoundCloudTrack(body);
        final tc = track.transcodings.firstWhere(
          (t) => t.mime.contains('mpeg'),
          orElse: () => track.transcodings.first,
        );
        final stream = await fetchText(
          Uri.parse(tc.url).replace(queryParameters: {
            'client_id': id,
            if (track.trackAuthorization != null) 'track_authorization': track.trackAuthorization!,
          }),
          proxy: proxy,
          headers: const {'Accept': 'application/json'},
        );
        return soundCloudInfo(track, parseSoundCloudStreamUrl(stream), uri.toString(), tc.mime);
      } on MediaException catch (e) {
        // An old client id answers 401/403: look it up again once.
        if (attempt == 0 && e.reason == 'loginRequired') continue;
        rethrow;
      }
    }
    throw const MediaException('parse');
  }

  Future<MediaInfo> _instagram(Uri uri) async {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final i = segs.indexWhere((s) => const {'p', 'reel', 'reels', 'tv'}.contains(s));
    if (i < 0 || i + 1 >= segs.length) throw const MediaException('unsupported');
    final kind = segs[i] == 'reels' ? 'reel' : segs[i];
    final code = segs[i + 1];
    final embed = Uri.https('www.instagram.com', '/$kind/$code/embed/captioned/');
    final html = await fetchText(embed, proxy: proxy, maxBytes: 6 * 1024 * 1024, headers: const {
      'Accept': 'text/html,application/xhtml+xml',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    });
    return parseInstagramEmbed(html, uri.toString(), expectsVideo: kind != 'p');
  }

  // ----------------------------------------------------------------- YouTube

  Future<MediaInfo> _youtube(Uri uri) async {
    final url = uri.toString();
    MediaException? last;

    // 1) youtube_explode_dart, with a hard time limit (a filtered network makes
    // it hang, which used to leave the dialog loading forever).
    try {
      return await _youtubeExplode(url).timeout(const Duration(seconds: 25));
    } on MediaException catch (e) {
      if (e.reason == 'notFound') rethrow;
      last = e;
    } on TimeoutException {
      last = const MediaException('network', 'timeout');
    } catch (e) {
      last = MediaException('blocked', e.toString());
    }

    // 2) YouTube's own player API as the Android VR app calls it: direct links
    // without a signature step.
    final id = youtubeVideoId(uri);
    if (id != null) {
      try {
        final body = await postJson(
          Uri.https('www.youtube.com', '/youtubei/v1/player', {'prettyPrint': 'false'}),
          innerTubePlayerRequest(id),
          proxy: proxy,
          timeout: const Duration(seconds: 25),
          headers: const {
            'User-Agent': innerTubeUserAgent,
            'X-YouTube-Client-Name': '28',
            'X-YouTube-Client-Version': '1.60.19',
            'Origin': 'https://www.youtube.com',
          },
        );
        return parseInnerTubePlayer(body, url);
      } on MediaException catch (e) {
        // Prefer the more specific reason when both paths failed.
        if (e.reason == 'notFound' || e.reason == 'loginRequired') rethrow;
        last = e;
      }
    }
    throw last ?? const MediaException('network');
  }

  Future<MediaInfo> _youtubeExplode(String url) async {
    // YoutubeExplode must use the SAME proxy as the download engine: YouTube
    // stream URLs are tied to the IP that requested them, and in countries where
    // YouTube is filtered the app's proxy (or the OS proxy) is the only way in.
    final io = createHttpClient(connectTimeout: const Duration(seconds: 15), proxy: proxy);
    final yt = YoutubeExplode(YoutubeHttpClient(IOClient(io)));
    try {
      final video = await yt.videos.get(url);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final formats = <MediaFormat>[];

      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      for (final s in muxed) {
        formats.add(MediaFormat(
          id: 'm${s.tag}',
          url: s.url.toString(),
          label: '${s.videoResolution.height}p ${s.container.name}',
          extension: s.container.name,
          sizeBytes: s.size.totalBytes,
        ));
      }
      final audio = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
      for (final s in audio) {
        formats.add(MediaFormat(
          id: 'a${s.tag}',
          url: s.url.toString(),
          label: 'Audio ${(s.bitrate.bitsPerSecond / 1000).round()} kbps ${s.container.name}',
          extension: s.container.name == 'mp4' ? 'm4a' : s.container.name,
          sizeBytes: s.size.totalBytes,
          hasVideo: false,
        ));
      }
      if (formats.isEmpty) throw const MediaException('notFound');
      return MediaInfo(
        platform: 'YouTube',
        title: video.title,
        sourcePage: url,
        uploader: video.author,
        thumbnail: video.thumbnails.highResUrl,
        duration: video.duration,
        formats: formats,
      );
    } on MediaException {
      rethrow;
    } on VideoUnavailableException {
      throw const MediaException('notFound');
    } on VideoRequiresPurchaseException {
      throw const MediaException('loginRequired');
    } on SocketException catch (e) {
      throw MediaException('network', e.message);
    } on YoutubeExplodeException catch (e) {
      throw MediaException('blocked', e.message);
    } finally {
      yt.close();
      io.close(force: true);
    }
  }

  // ------------------------------------------------------------ Reddit/Telegram

  Future<MediaInfo> _reddit(Uri uri) async {
    // Short links (redd.it/xxxx) are followed by the HTTP layer.
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    final jsonUri = Uri(
      scheme: 'https',
      host: uri.host == 'redd.it' ? 'www.reddit.com' : uri.host,
      path: uri.host == 'redd.it' ? '/comments${path}' : '$path.json',
      queryParameters: {'raw_json': '1'},
    );
    final body = await fetchText(jsonUri, proxy: proxy, headers: const {
      'Accept': 'application/json',
    });
    return parseRedditJson(body, uri.toString());
  }

  Future<MediaInfo> _telegram(Uri uri) async {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final embed = Uri(
      scheme: 'https',
      host: 't.me',
      path: '/${segs[0] == 's' && segs.length >= 3 ? segs[1] : segs[0]}/${segs.last}',
      queryParameters: {'embed': '1', 'mode': 'tme'},
    );
    final html = await fetchText(embed, proxy: proxy);
    return parseTelegramEmbed(html, uri.toString());
  }

  // ------------------------------------------------------------------ yt-dlp

  /// Returns null when yt-dlp is not installed or does not support the page,
  /// so the caller falls back to the built-in adapters.
  Future<MediaInfo?> _tryYtDlp(String url) async {
    final exe = ytDlpPath ?? 'yt-dlp';
    try {
      final args = <String>[
        '--dump-single-json',
        '--no-playlist',
        '--no-warnings',
        '--socket-timeout', '20',
        if (proxy.mode == ProxyMode.manual && proxy.isManualValid)
          ...['--proxy', 'http://${proxy.host}:${proxy.port}'],
        if (proxy.mode == ProxyMode.none && FilterBypass.port == null) ...['--proxy', ''],
        if (proxy.mode != ProxyMode.manual && FilterBypass.port != null)
          ...['--proxy', 'http://127.0.0.1:${FilterBypass.port}'],
        '--',
        url,
      ];
      final r = await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8)
          .timeout(const Duration(seconds: 40));
      if (r.exitCode != 0) return null;
      return parseYtDlpJson(r.stdout as String, url);
    } on ProcessException {
      return null; // not installed
    } on TimeoutException {
      return null;
    } on MediaException {
      return null;
    }
  }

  /// True when a yt-dlp executable can be started.
  Future<bool> ytDlpAvailable() async {
    try {
      final r = await Process.run(ytDlpPath ?? 'yt-dlp', ['--version'])
          .timeout(const Duration(seconds: 10));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
