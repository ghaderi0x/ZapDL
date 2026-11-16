import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/checksum.dart';
import '../engine/engine.dart';
import '../engine/errors.dart';
import '../engine/http_support.dart';
import '../engine/models.dart';
import '../engine/store.dart';
import '../media/media_http.dart';
import '../media/media_models.dart';
import 'asset_selector.dart';
import 'release.dart';
import 'semver.dart';

/// Machine-readable update failures; the UI maps them to localized text.
class UpdateException implements Exception {
  const UpdateException(this.code, [this.detail]);

  /// network | rateLimited | parse | noAsset | download | checksum | install | unsupported
  final String code;
  final String? detail;

  @override
  String toString() => 'UpdateException($code${detail == null ? '' : ': $detail'})';
}

class CheckResult {
  const CheckResult({
    required this.release,
    required this.newer,
    required this.checkedAt,
    this.fromCache = false,
  });

  /// Newest release found, or null if the repository has none.
  final ReleaseInfo? release;

  /// True when [release] is newer than the running version.
  final bool newer;
  final DateTime checkedAt;
  final bool fromCache;
}

enum InstallOutcome {
  /// An installer was started; the app should exit so it can replace files.
  launchedExit,

  /// The system installer/viewer was opened for the user (Android, macOS).
  openedForUser,

  /// The file was shown in the file manager; the user finishes manually.
  revealed,
}

abstract class UpdateInstaller {
  Future<InstallOutcome> install(String path, UpdatePlatform platform);
}

/// Checks GitHub Releases, downloads and verifies update files.
///
/// Release assets and their naming are defined in asset_selector.dart and
/// produced by .github/workflows/release.yml.
class UpdateService {
  UpdateService({
    required this.prefs,
    required this.currentVersion,
    required this.updatesDir,
    required this.platform,
    required this.arch,
    required this.installer,
    this.repo = 'ghaderi0x/ZapDL',
    this.apiBase = 'https://api.github.com',
    this.proxy = const ProxyConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SharedPreferences prefs;
  final SemVer currentVersion;
  final String updatesDir;
  final UpdatePlatform platform;
  final String arch;
  final UpdateInstaller installer;
  final String repo;
  final String apiBase;
  ProxyConfig proxy;
  final DateTime Function() _clock;

  static const autoCheckInterval = Duration(hours: 24);
  static const _kEtag = 'update.etag';
  static const _kBody = 'update.body';
  static const _kChecked = 'update.checkedAt';
  static const _kChannel = 'update.pre';

  String get releasesUrl => 'https://github.com/$repo/releases';

  DateTime? get lastChecked {
    final ms = prefs.getInt(_kChecked);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Whether a background check is due (never more than once per 24 hours).
  bool autoCheckDue({required bool enabled}) {
    if (!enabled) return false;
    final last = lastChecked;
    return last == null || _clock().difference(last) >= autoCheckInterval;
  }

  /// Asks GitHub for the newest release. Uses the cached answer when it is
  /// fresh (unless [force]) and a conditional request otherwise, so a check
  /// that finds nothing new costs no rate limit.
  Future<CheckResult> check({bool includePrereleases = false, bool force = false}) async {
    final cached = prefs.getString(_kBody);
    final cachedChannel = prefs.getBool(_kChannel) ?? false;
    final channelSame = cachedChannel == includePrereleases;
    final last = lastChecked;
    if (!force &&
        cached != null &&
        channelSame &&
        last != null &&
        _clock().difference(last) < const Duration(hours: 1)) {
      return _result(cached, includePrereleases, last, fromCache: true);
    }

    final uri = Uri.parse(
      includePrereleases
          ? '$apiBase/repos/$repo/releases?per_page=15'
          : '$apiBase/repos/$repo/releases/latest',
    );
    final etag = channelSame ? prefs.getString(_kEtag) : null;
    final client = createHttpClient(
      connectTimeout: const Duration(seconds: 15),
      proxy: proxy,
    );
    try {
      final opened = await openGet(
        client,
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          if (etag != null) 'If-None-Match': etag,
        },
        timeout: const Duration(seconds: 20),
      );
      final res = opened.response;
      final now = _clock();
      if (res.statusCode == 304 && cached != null) {
        await res.drain<void>();
        await prefs.setInt(_kChecked, now.millisecondsSinceEpoch);
        return _result(cached, includePrereleases, now);
      }
      if (res.statusCode == 404) {
        // No published release yet.
        await res.drain<void>();
        await prefs.setInt(_kChecked, now.millisecondsSinceEpoch);
        return CheckResult(release: null, newer: false, checkedAt: now);
      }
      if (res.statusCode == 403 || res.statusCode == 429) {
        await res.drain<void>();
        throw const UpdateException('rateLimited');
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('network', '${res.statusCode}');
      }
      final body = await utf8.decodeStream(res.timeout(const Duration(seconds: 20)));
      final newTag = res.headers.value(HttpHeaders.etagHeader);
      final result = _result(body, includePrereleases, now);
      await prefs.setString(_kBody, body);
      await prefs.setBool(_kChannel, includePrereleases);
      await prefs.setInt(_kChecked, now.millisecondsSinceEpoch);
      if (newTag != null) {
        await prefs.setString(_kEtag, newTag);
      } else {
        await prefs.remove(_kEtag);
      }
      return result;
    } on UpdateException {
      rethrow;
    } on DownloadFailure catch (f) {
      throw UpdateException('network', f.code.name);
    } on SocketException catch (e) {
      throw UpdateException('network', e.message);
    } on TimeoutException {
      throw const UpdateException('network', 'timeout');
    } finally {
      client.close(force: true);
    }
  }

  CheckResult _result(String body, bool pre, DateTime at, {bool fromCache = false}) {
    final release = ReleaseInfo.parse(body, includePrereleases: pre);
    if (release == null && body.trim().isNotEmpty) {
      // An empty/odd list is "no release"; unparsable JSON is an error.
      try {
        jsonDecode(body);
      } on FormatException {
        throw const UpdateException('parse');
      }
    }
    return CheckResult(
      release: release,
      newer: release != null && release.version > currentVersion,
      checkedAt: at,
      fromCache: fromCache,
    );
  }

  ReleaseAsset? assetFor(ReleaseInfo r) =>
      selectAsset(r.assets, platform: platform, arch: arch);

  /// The trusted SHA-256 for [asset]: GitHub's own digest if present, else the
  /// release's SHA256SUMS.txt. Null when the release provides neither.
  Future<String?> expectedChecksum(ReleaseInfo r, ReleaseAsset asset) async {
    if (asset.sha256 != null) return asset.sha256;
    final sums = checksumAssetName(r.assets);
    if (sums == null) return null;
    final url = r.assets.firstWhere((a) => a.name == sums).url;
    try {
      final text = await fetchText(Uri.parse(url), proxy: proxy, maxBytes: 256 * 1024);
      return parseChecksumFile(text)[asset.name];
    } on MediaException {
      return null;
    }
  }

  DownloadEngine? _engine;

  /// Downloads [asset] with the app's own engine (resumable, retrying) and
  /// verifies its SHA-256. [onProgress] gets (received, total, bytesPerSecond).
  /// Returns the verified file. When no checksum is published,
  /// [verified] in the result is false and the UI says so.
  Future<({File file, bool verified})> download(
    ReleaseInfo release,
    ReleaseAsset asset, {
    void Function(int received, int total, double speed)? onProgress,
  }) async {
    final expected = await expectedChecksum(release, asset);
    await Directory(updatesDir).create(recursive: true);
    final engine = _engine ??= DownloadEngine(
      store: JsonFileDownloadStore(File(p.join(updatesDir, 'updates.json'))),
      partsRoot: p.join(updatesDir, 'parts'),
      config: EngineConfig(connections: 4, maxRetries: 4)..proxy = proxy,
    );
    engine.config.proxy = proxy;
    if (!_engineReady) {
      await engine.init();
      _engineReady = true;
    }

    DownloadTask? task;
    for (final t in engine.snapshot) {
      if (t.url == asset.url) task = t;
    }
    if (task != null && task.status == DownloadStatus.completed) {
      final f = File(task.finalPath);
      if (!await f.exists()) {
        await engine.remove(task.id);
        task = null;
      }
    }
    if (task == null) {
      // Old update files are no longer useful.
      for (final t in engine.snapshot) {
        await engine.remove(t.id, deleteFile: true);
      }
      try {
        task = await engine.add(
          url: asset.url,
          directory: updatesDir,
          fileName: asset.name,
        );
      } on DownloadFailure catch (f) {
        throw UpdateException('download', f.code.name);
      }
    } else if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.canceled) {
      await engine.resume(task.id);
    }

    final id = task.id;
    final done = Completer<DownloadTask>();
    late StreamSubscription<List<DownloadTask>> sub;
    void handle(List<DownloadTask> tasks) {
      final t = tasks.where((x) => x.id == id).firstOrNull;
      if (t == null) return;
      onProgress?.call(t.receivedBytes, t.totalBytes, t.speedBps);
      if (t.status == DownloadStatus.completed && !done.isCompleted) done.complete(t);
      if (t.status == DownloadStatus.failed && !done.isCompleted) {
        done.completeError(UpdateException('download', t.errorCode?.name));
      }
    }

    sub = engine.updates.listen(handle);
    handle(engine.snapshot);
    final DownloadTask finished;
    try {
      finished = await done.future;
    } finally {
      await sub.cancel();
    }

    final file = File(finished.finalPath);
    if (expected != null) {
      final ok = await verifyChecksum(file, ChecksumAlgorithm.sha256, expected);
      if (!ok) {
        await engine.remove(id, deleteFile: true);
        throw const UpdateException('checksum');
      }
    }
    return (file: file, verified: expected != null);
  }

  bool _engineReady = false;

  /// Stops an in-progress update download, keeping partial data for resume.
  void pauseDownload() => _engine?.pauseAll();

  /// Verifies a user-supplied update file against an optional `<file>.sha256`
  /// sidecar. Returns true (verified), false (mismatch) or null (no sidecar).
  Future<bool?> verifyLocalFile(File file) async {
    final side = File('${file.path}.sha256');
    if (!await side.exists()) return null;
    final text = await side.readAsString();
    final sums = parseChecksumFile(text);
    final expected = sums[p.basename(file.path)] ??
        RegExp(r'^[0-9a-fA-F]{64}').firstMatch(text.trim())?.group(0)?.toLowerCase();
    if (expected == null) return null;
    return verifyChecksum(file, ChecksumAlgorithm.sha256, expected);
  }

  Future<InstallOutcome> install(File file) async {
    if (!isInstallableFile(file.path, platform)) {
      throw const UpdateException('unsupported');
    }
    try {
      return await installer.install(file.path, platform);
    } catch (e) {
      throw UpdateException('install', '$e');
    }
  }

  Future<void> dispose() async {
    await _engine?.shutdown();
    _engine = null;
    _engineReady = false;
  }
}
