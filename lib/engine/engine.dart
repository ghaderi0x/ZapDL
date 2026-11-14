import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'errors.dart';
import 'cookies.dart';
import 'file_utils.dart';
import 'http_support.dart';
import 'models.dart';
import 'parts.dart';
import 'probe.dart';
import 'runner.dart';
import 'store.dart';

/// Why the engine is currently not starting new transfers.
enum EngineGate {
  /// Transfers may run.
  open,

  /// The app is suspended (e.g. iOS in the background): everything waits and
  /// resumes automatically when the app returns.
  suspended,

  /// The network policy forbids transfers (offline, or Wi-Fi-only on mobile data).
  network,

  /// Outside the allowed daily schedule window.
  schedule,
}

/// Download manager: queue, concurrency, pause/resume, retry, persistence.
/// Pure Dart (no Flutter imports) so it is independently testable.
class DownloadEngine {
  DownloadEngine({
    required this.store,
    required this.partsRoot,
    EngineConfig? config,
    this.tickInterval = const Duration(milliseconds: 500),
    this.logger,
    SecretStore? secrets,
    DateTime Function()? clock,
  })  : config = config ?? EngineConfig(),
        secrets = secrets ?? InMemorySecretStore(),
        _clock = clock ?? DateTime.now;

  final DownloadStore store;
  final String partsRoot;
  final EngineConfig config;
  final Duration tickInterval;

  /// Credentials of downloads (Cookie, Authorization). Never in the JSON store.
  final SecretStore secrets;
  final DateTime Function() _clock;

  /// Optional sink for diagnostic lines. The engine never passes URLs,
  /// headers or credentials to it.
  final void Function(String message)? logger;

  final List<DownloadTask> _tasks = [];
  final Map<String, SegmentedRunner> _runners = {};
  final Map<String, Future<void>> _executions = {};
  final StreamController<List<DownloadTask>> _updates = StreamController.broadcast();
  Timer? _ticker;
  bool _needsSave = false;
  bool _saving = false;
  int _ticksSinceSave = 0;
  bool _disposed = false;
  bool _networkAllowed = true;
  bool _suspended = false;
  EngineGate _gate = EngineGate.open;
  final StreamController<EngineGate> _gateUpdates = StreamController.broadcast();

  Stream<List<DownloadTask>> get updates => _updates.stream;

  /// Current gate; see [EngineGate].
  EngineGate get gate => _gate;
  Stream<EngineGate> get gateUpdates => _gateUpdates.stream;
  List<DownloadTask> get snapshot => _tasks.map((t) => t.copy()).toList(growable: false);

  /// Loads saved downloads. A download saved as "downloading" was interrupted
  /// by an exit or crash: it becomes paused, or queued when [resumeInterrupted].
  Future<void> init({bool resumeInterrupted = false}) async {
    final loaded = await store.load();
    for (final t in loaded) {
      if (t.status == DownloadStatus.downloading) {
        t.status = resumeInterrupted ? DownloadStatus.queued : DownloadStatus.paused;
      }
      t.speedBps = 0;
      if (!t.isFinished) {
        try {
          t.secretHeaders.addAll(await secrets.read(t.id));
        } catch (_) {
          // Unreadable secure storage: the download may fail with accessDenied
          // later instead of crashing startup.
        }
      }
      _tasks.add(t);
    }
    _updateGate();
    _ticker = Timer.periodic(tickInterval, (_) => _tick());
    for (final t in _tasks) {
      if (t.status == DownloadStatus.completed) t.fileMissing = !File(t.finalPath).existsSync();
    }
    _emit();
    _pump();
  }

  /// Builds the stored URL, storable headers and credentials for a request.
  /// [cookies] may be a cookies.txt export or a raw "a=b; c=d" string.
  /// Throws [DownloadFailure] for invalid headers/cookies.
  ({String url, Map<String, String> headers, Map<String, String> secrets}) prepareRequest(
    String url, {
    Map<String, String> headers = const {},
    String? cookies,
  }) {
    final info = extractUserInfo(url);
    final all = {...headers};
    final uri = parseDownloadUri(info.url);
    if (cookies != null) {
      final header = cookieHeaderFromInput(cookies, uri, now: _clock());
      if (header != null) all['Cookie'] = header;
    }
    final split = splitHeaders(all);
    final secret = {...split.secret};
    final hasAuth = secret.keys.any((k) => k.toLowerCase() == 'authorization');
    if (info.authorization != null && !hasAuth) {
      secret['Authorization'] = info.authorization!;
    }
    return (url: info.url, headers: split.plain, secrets: secret);
  }

  Future<ProbeResult> probe(
    String url, {
    Map<String, String> headers = const {},
    String? cookies,
  }) {
    final req = prepareRequest(url, headers: headers, cookies: cookies);
    return probeUrl(
      req.url,
      connectTimeout: config.connectTimeout,
      headers: req.headers,
      secretHeaders: req.secrets,
      proxy: config.proxy,
    );
  }

  Future<DownloadTask> add({
    required String url,
    required String directory,
    String? fileName,
    ProbeResult? probe,
    Map<String, String> headers = const {},
    String? cookies,
    DateTime? scheduledAt,
    String? sourcePage,
    String? groupId,
    int groupOrder = 0,
    bool autoNext = false,
  }) async {
    final req = prepareRequest(url, headers: headers, cookies: cookies);
    final pr = probe ??
        await probeUrl(
          req.url,
          connectTimeout: config.connectTimeout,
          headers: req.headers,
          secretHeaders: req.secrets,
          proxy: config.proxy,
        );
    final custom = fileName?.trim() ?? '';
    final task = DownloadTask(
      id: _newId(),
      url: req.url,
      headers: req.headers,
      secretHeaders: req.secrets,
      scheduledAt: scheduledAt,
      sourcePage: sourcePage,
      groupId: groupId,
      groupOrder: groupOrder,
      autoNext: autoNext,
      fileName: sanitizeFileName(custom.isNotEmpty ? custom : pr.fileName),
      directory: directory,
      totalBytes: pr.totalBytes,
      rangeSupported: pr.rangeSupported,
      etag: pr.etag,
      lastModified: pr.lastModified,
      mimeType: pr.mimeType,
      connections: config.connections,
      segments: planSegments(
        total: pr.totalBytes,
        ranges: pr.rangeSupported,
        connections: config.connections,
        minSegmentBytes: config.minSegmentBytes,
      ),
    );
    if (task.secretHeaders.isNotEmpty) {
      try {
        await secrets.write(task.id, task.secretHeaders);
      } catch (_) {}
    }
    _tasks.add(task);
    _changed();
    _pump();
    return task.copy();
  }

  /// Sets or clears the start time of a download. A running download that is
  /// scheduled for later is stopped and kept queued.
  void schedule(String id, DateTime? at) {
    final t = _find(id);
    if (t == null || t.isFinished) return;
    t.scheduledAt = at;
    if (at != null && _clock().isBefore(at) && t.status == DownloadStatus.downloading) {
      _stopToQueue(t);
    }
    if (at != null && t.status == DownloadStatus.paused) {
      t
        ..status = DownloadStatus.queued
        ..errorCode = null
        ..errorDetail = null;
    }
    _changed();
    _pump();
  }

  /// Network policy (offline / Wi-Fi-only). While false nothing transfers and
  /// running downloads wait in the queue; they restart when it turns true.
  void setNetworkAllowed(bool allowed) {
    if (_networkAllowed == allowed) return;
    _networkAllowed = allowed;
    _applyGate();
  }

  /// App suspension (iOS background). Waiting downloads resume automatically.
  void setSuspended(bool suspended) {
    if (_suspended == suspended) return;
    _suspended = suspended;
    _applyGate();
  }

  /// Re-queues downloads that failed only because of the network (call when
  /// connectivity returns). Returns how many were re-queued.
  int retryNetworkFailures() {
    var n = 0;
    for (final t in _tasks) {
      if (t.status == DownloadStatus.failed &&
          !t.needsRestart &&
          (t.errorCode == DownloadErrorCode.network ||
              t.errorCode == DownloadErrorCode.timeout)) {
        t
          ..status = DownloadStatus.queued
          ..errorCode = null
          ..errorDetail = null;
        n++;
      }
    }
    if (n > 0) {
      _changed();
      _pump();
    }
    return n;
  }

  void pause(String id) {
    final t = _find(id);
    if (t == null) return;
    if (t.status != DownloadStatus.downloading && t.status != DownloadStatus.queued) return;
    t.status = DownloadStatus.paused;
    t.speedBps = 0;
    _runners[id]?.stop();
    _changed();
    _pump();
  }

  void pauseAll() {
    for (final t in List.of(_tasks)) {
      pause(t.id);
    }
  }

  /// Resumes a paused download, or retries a failed/canceled one.
  Future<void> resume(String id) async {
    final t = _find(id);
    if (t == null) return;
    switch (t.status) {
      case DownloadStatus.paused:
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        if (t.needsRestart || t.status == DownloadStatus.canceled) {
          await _resetForRestart(t);
        }
        t
          ..status = DownloadStatus.queued
          ..errorCode = null
          ..errorDetail = null;
        _changed();
        _pump();
      case DownloadStatus.queued:
      case DownloadStatus.downloading:
      case DownloadStatus.completed:
        break;
    }
  }

  Future<void> resumeAll() async {
    for (final t in List.of(_tasks)) {
      if (t.status == DownloadStatus.paused) await resume(t.id);
    }
  }

  Future<void> cancel(String id) async {
    final t = _find(id);
    if (t == null || t.status == DownloadStatus.completed) return;
    t.status = DownloadStatus.canceled;
    t.speedBps = 0;
    _runners[id]?.stop();
    await _executions[id];
    await _resetForRestart(t);
    _changed();
    _pump();
  }

  Future<void> remove(String id, {bool deleteFile = false}) async {
    final t = _find(id);
    if (t == null) return;
    _runners[id]?.stop();
    await _executions[id];
    await _deleteParts(t);
    if (deleteFile && t.status == DownloadStatus.completed) {
      try {
        final f = File(t.finalPath);
        if (isInside(t.directory, f.path) && await f.exists()) await f.delete();
      } catch (_) {}
    }
    _tasks.removeWhere((x) => x.id == id);
    await _forgetSecrets(t);
    _changed();
    _pump();
  }

  void setPriority(String id, int priority) {
    final t = _find(id);
    if (t == null) return;
    t.priority = priority;
    _changed();
    _pump();
  }

  /// Call when settings change (concurrency, schedule window, proxy).
  void configChanged() => _applyGate();

  /// Deletes partial-download folders that no remaining download can use
  /// (for example left behind by a crash after the record was removed).
  /// Folders of queued, running, paused and failed (retryable) downloads are
  /// kept. Returns the number of bytes freed.
  Future<int> cleanOrphanedParts() async {
    final root = Directory(partsRoot);
    if (!await root.exists()) return 0;
    final keep = <String>{
      for (final t in _tasks)
        if (t.status != DownloadStatus.completed && t.status != DownloadStatus.canceled) t.id,
    };
    final dirs = await root
        .list(followLinks: false)
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    var freed = 0;
    for (final dir in dirs) {
      if (keep.contains(p.basename(dir.path))) continue;
      try {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is File) freed += await f.length();
        }
        await dir.delete(recursive: true);
      } catch (_) {
        // Best effort: a folder that cannot be removed is simply left in place.
      }
    }
    return freed;
  }

  /// Stops everything and saves. By default running/queued downloads are saved
  /// as paused; with [keepQueued] they keep their state (a running download is
  /// saved as queued) so the next start can resume them with
  /// `init(resumeInterrupted: true)`.
  Future<void> shutdown({bool keepQueued = false}) async {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    for (final t in _tasks) {
      if (t.status == DownloadStatus.downloading) {
        t.status = keepQueued ? DownloadStatus.queued : DownloadStatus.paused;
      } else if (t.status == DownloadStatus.queued && !keepQueued) {
        t.status = DownloadStatus.paused;
      }
      t.speedBps = 0;
    }
    for (final r in _runners.values) {
      r.stop();
    }
    await Future.wait(_executions.values.map((f) => f.catchError((Object _) {})));
    await store.save(_tasks);
    await _updates.close();
    await _gateUpdates.close();
  }

  // ---------------------------------------------------------------- internals

  DownloadTask? _find(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${math.Random().nextInt(1 << 20).toRadixString(36)}';

  String _partsDir(DownloadTask t) => p.join(partsRoot, t.id);

  Future<void> _forgetSecrets(DownloadTask t) async {
    t.secretHeaders.clear();
    try {
      await secrets.delete(t.id);
    } catch (_) {}
  }

  EngineGate _computeGate() {
    if (_suspended) return EngineGate.suspended;
    if (!_networkAllowed) return EngineGate.network;
    final w = config.allowedWindow;
    if (w != null && !w.contains(_clock())) return EngineGate.schedule;
    return EngineGate.open;
  }

  void _updateGate() {
    final g = _computeGate();
    if (g == _gate) return;
    _gate = g;
    if (!_gateUpdates.isClosed) _gateUpdates.add(g);
  }

  /// Re-evaluates the gate; stops running downloads when it closes.
  void _applyGate() {
    if (_disposed) return;
    _updateGate();
    if (_gate != EngineGate.open) {
      var any = false;
      for (final t in _tasks) {
        if (t.status == DownloadStatus.downloading) {
          _stopToQueue(t);
          any = true;
        }
      }
      if (any) _changed();
    }
    _pump();
  }

  /// Stops a transfer but keeps it queued so it restarts by itself.
  void _stopToQueue(DownloadTask t) {
    t.status = DownloadStatus.queued;
    t.speedBps = 0;
    _runners[t.id]?.stop();
  }

  bool _due(DownloadTask t) {
    final at = t.scheduledAt;
    return at == null || !_clock().isBefore(at);
  }

  Future<void> _deleteParts(DownloadTask t) async {
    try {
      final d = Directory(_partsDir(t));
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _resetForRestart(DownloadTask t) async {
    await _deleteParts(t);
    t.segments.clear(); // re-probed and re-planned on next start
    t.receivedBytes = 0;
    t.needsRestart = false;
    t.etag = null;
    t.lastModified = null;
  }

  void _pump() {
    if (_disposed || _gate != EngineGate.open) return;
    final active = _tasks.where((t) => t.status == DownloadStatus.downloading).length;
    var slots = config.maxConcurrent - active;
    if (slots <= 0) return;
    final queued = _tasks
        .where((t) => t.status == DownloadStatus.queued && _due(t) && _groupReady(t))
        .toList()
      ..sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        return byPriority != 0 ? byPriority : a.createdAt.compareTo(b.createdAt);
      });
    for (final t in queued) {
      if (slots <= 0) break;
      _launch(t);
      slots--;
    }
  }

  /// A grouped download waits until every earlier one in its group is done,
  /// failed or canceled (queued, running and paused ones block it).
  bool _groupReady(DownloadTask t) {
    final g = t.groupId;
    if (g == null) return true;
    return !_tasks.any((o) =>
        o.groupId == g &&
        o.groupOrder < t.groupOrder &&
        (o.status == DownloadStatus.queued ||
            o.status == DownloadStatus.downloading ||
            o.status == DownloadStatus.paused));
  }

  /// Marks finished downloads whose file was deleted outside the app.
  /// Returns true when anything changed.
  bool refreshMissingFiles() {
    var changed = false;
    for (final t in _tasks) {
      if (t.status != DownloadStatus.completed) {
        if (t.fileMissing) {
          t.fileMissing = false;
          changed = true;
        }
        continue;
      }
      bool missing;
      try {
        missing = !File(t.finalPath).existsSync();
      } catch (_) {
        missing = false;
      }
      if (missing != t.fileMissing) {
        t.fileMissing = missing;
        changed = true;
      }
    }
    if (changed) _emit();
    return changed;
  }

  /// After part N completes, look for part N+1 and queue it if it exists.
  Future<void> _addNextPart(DownloadTask done) async {
    final next = nextPartUrl(done.url);
    if (_disposed || next == null || _tasks.any((x) => x.url == next)) return;
    try {
      await add(
        url: next,
        directory: done.directory,
        headers: {...done.headers, ...done.secretHeaders},
        groupId: done.groupId,
        groupOrder: done.groupOrder + 1,
        autoNext: true,
      );
    } catch (_) {
      // No next part (404 and friends): the chain simply ends here.
    }
  }

  void _launch(DownloadTask t) {
    t.scheduledAt = null; // the scheduled time has arrived
    t.status = DownloadStatus.downloading;
    t.errorCode = null;
    t.errorDetail = null;
    final runner = SegmentedRunner(task: t, partsDir: _partsDir(t), config: config);
    _runners[t.id] = runner;
    // Wait for a previous (paused) execution to release its files first.
    final previous = _executions[t.id] ?? Future<void>.value();
    final run = previous.then((_) => _execute(t, runner));
    _executions[t.id] = run;
    _changed();
  }

  Future<void> _execute(DownloadTask t, SegmentedRunner runner) async {
    var attempt = 0;
    try {
      if (runner.stopped) return;
      while (true) {
        try {
          await runner.run();
          t
            ..status = DownloadStatus.completed
            ..completedAt = DateTime.now()
            ..receivedBytes = t.totalBytes > 0 ? t.totalBytes : t.receivedBytes
            ..speedBps = 0
            ..errorCode = null;
          logger?.call('download ${t.id} completed');
          if (t.autoNext) unawaited(_addNextPart(t.copy())); // copy keeps the cookies
          await _forgetSecrets(t);
          return;
        } catch (e) {
          if (runner.stopped) return;
          final failure = DownloadFailure.from(e);
          if (failure.retryable && attempt < config.maxRetries) {
            attempt++;
            final wait = config.retryBackoffUnit * (1 << (attempt - 1));
            final until = DateTime.now().add(wait);
            while (!runner.stopped && DateTime.now().isBefore(until)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            if (runner.stopped) return;
            continue;
          }
          // Never mark an incomplete download as completed.
          t
            ..status = DownloadStatus.failed
            ..errorCode = failure.code
            ..errorDetail = failure.detail
            ..needsRestart = failure.needsRestart
            ..speedBps = 0;
          logger?.call('download ${t.id} failed: ${failure.code.name}');
          return;
        }
      }
    } finally {
      if (identical(_runners[t.id], runner)) _runners.remove(t.id);
      t.receivedBytes = t.status == DownloadStatus.completed
          ? t.receivedBytes
          : t.segments.fold<int>(0, (a, s) => a + s.received);
      _changed();
      _pump();
    }
  }

  int _missingTicks = 0;

  void _tick() {
    if (_disposed) return;
    if (++_missingTicks >= 10) {
      _missingTicks = 0;
      refreshMissingFiles();
    }
    // Time-based gates: the schedule window opening/closing and scheduled starts.
    _applyGate();
    var active = false;
    final seconds = tickInterval.inMilliseconds / 1000.0;
    for (final t in _tasks) {
      final r = _runners[t.id];
      if (t.status == DownloadStatus.downloading && r != null) {
        final inst = r.takeTickBytes() / seconds;
        t.speedBps = t.speedBps == 0 ? inst : t.speedBps * 0.6 + inst * 0.4;
        t.receivedBytes = t.segments.fold<int>(0, (a, s) => a + s.received);
        active = true;
      } else if (t.speedBps != 0) {
        t.speedBps = 0;
        active = true;
      }
    }
    if (active) {
      _needsSave = true;
      _emit();
    }
    if (_needsSave && ++_ticksSinceSave >= 4) {
      _ticksSinceSave = 0;
      _save();
    }
  }

  /// State changed in a way that should be shown and saved immediately.
  void _changed() {
    _emit();
    _save();
  }

  void _emit() {
    if (_disposed || _updates.isClosed) return;
    _updates.add(snapshot);
  }

  void _save() {
    if (_saving || _disposed) {
      _needsSave = true;
      return;
    }
    _saving = true;
    _needsSave = false;
    store.save(_tasks).catchError((Object _) {}).whenComplete(() {
      _saving = false;
    });
  }
}
