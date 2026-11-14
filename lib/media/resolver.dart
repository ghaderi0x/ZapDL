import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/io_client.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../engine/http_support.dart';
import '../engine/models.dart';
import 'adapters.dart';
import 'media_http.dart';
import 'media_models.dart';

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

  /// True for URLs that are a page to extract from rather than a direct file.
  static bool looksLikePage(Uri u) {
    if (isYouTube(u) || isReddit(u) || isTelegram(u)) return true;
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
    final url = uri.toString();

    if (isYouTube(uri)) return _youtube(url);

    if (_desktop) {
      final viaYtDlp = await _tryYtDlp(url);
      if (viaYtDlp != null) return viaYtDlp;
    }
    if (isReddit(uri)) return _reddit(uri);
    if (isTelegram(uri)) return _telegram(uri);

    final html = await fetchText(uri, proxy: proxy, headers: const {
      'Accept': 'text/html,application/xhtml+xml',
    });
    return parseOpenGraph(html, url);
  }

  // ----------------------------------------------------------------- YouTube

  Future<MediaInfo> _youtube(String url) async {
    // YoutubeExplode must use the SAME proxy as the download engine: YouTube
    // stream URLs are tied to the IP that requested them, and in countries where
    // YouTube is filtered the app's proxy (or the OS proxy) is the only way in.
    final io = createHttpClient(connectTimeout: const Duration(seconds: 20), proxy: proxy);
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
      path: uri.host == 'redd.it' ? '/comments$path' : '$path.json',
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
        if (proxy.mode == ProxyMode.none) ...['--proxy', ''],
        '--',
        url,
      ];
      final r = await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8)
          .timeout(const Duration(seconds: 60));
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
