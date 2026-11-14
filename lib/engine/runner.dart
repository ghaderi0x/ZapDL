import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors.dart';
import 'file_utils.dart';
import 'http_support.dart';
import 'models.dart';
import 'probe.dart';

/// Executes one download attempt: plans/validates segments, downloads them
/// concurrently into separate part files, then merges them safely.
///
/// Resume strategy: each segment has its own part file. On every run the real
/// part-file length is the source of truth for how much was received, so a
/// crash can never make us skip or duplicate bytes.
class SegmentedRunner {
  SegmentedRunner({
    required this.task,
    required this.partsDir,
    required this.config,
  });

  final DownloadTask task;
  final String partsDir;
  final EngineConfig config;

  bool _stopped = false;
  final List<HttpClient> _clients = [];
  final Stopwatch _clock = Stopwatch();
  int _throttledBytes = 0;
  int _tickBytes = 0;

  bool get stopped => _stopped;

  /// Called by the engine ticker to compute speed.
  int takeTickBytes() {
    final b = _tickBytes;
    _tickBytes = 0;
    return b;
  }

  void stop() {
    _stopped = true;
    _closeClients();
  }

  void _closeClients() {
    final clients = List<HttpClient>.of(_clients);
    _clients.clear();
    for (final c in clients) {
      try {
        c.close(force: true);
      } catch (_) {}
    }
  }

  void _check() {
    if (_stopped) throw const StoppedException();
  }

  Future<void> run() async {
    _check();
    _clock
      ..reset()
      ..start();
    _throttledBytes = 0;

    await Directory(task.directory).create(recursive: true);
    await Directory(partsDir).create(recursive: true);

    if (task.segments.isEmpty) {
      await _plan();
    } else {
      await _syncFromDisk();
      if (task.segments.any((s) => s.received > 0)) {
        await _validateRemote();
      }
    }
    _check();

    Object? firstError;
    final jobs = <Future<void>>[];
    for (var i = 0; i < task.segments.length; i++) {
      if (task.segments[i].isDone) continue;
      jobs.add(_downloadSegment(i).catchError((Object e) {
        if (firstError == null && !_stopped) {
          firstError = e;
          _closeClients(); // abort sibling segments
        }
      }));
    }
    await Future.wait(jobs);
    _check();
    if (firstError != null) throw firstError!;

    // Unknown-length downloads learn their size when the stream ends.
    if (task.totalBytes <= 0 && task.segments.length == 1) {
      final s = task.segments.first;
      s.end = s.start + s.received - 1;
      task.totalBytes = s.received;
    }
    await _finalize();
  }

  Future<ProbeResult> _probe() => probeUrl(
        task.url,
        connectTimeout: config.connectTimeout,
        headers: task.headers,
        secretHeaders: task.secretHeaders,
        proxy: config.proxy,
      );

  Future<void> _plan() async {
    final probe = await _probe();
    task.totalBytes = probe.totalBytes;
    task.rangeSupported = probe.rangeSupported;
    task.etag = probe.etag;
    task.lastModified = probe.lastModified;
    task.mimeType = probe.mimeType;
    task.segments
      ..clear()
      ..addAll(planSegments(
        total: probe.totalBytes,
        ranges: probe.rangeSupported,
        connections: task.connections,
        minSegmentBytes: config.minSegmentBytes,
      ));
  }

  /// Aligns in-memory progress with what is really on disk.
  Future<void> _syncFromDisk() async {
    for (var i = 0; i < task.segments.length; i++) {
      final seg = task.segments[i];
      final file = File(partFileName(partsDir, i));
      var existing = await file.exists() ? await file.length() : 0;

      if (!task.rangeSupported) {
        // Cannot resume mid-stream: start over.
        if (existing > 0) await file.delete();
        existing = 0;
      } else if (seg.end >= 0 && existing > seg.length) {
        final raf = await file.open(mode: FileMode.append);
        try {
          await raf.truncate(seg.length);
        } finally {
          await raf.close();
        }
        existing = seg.length;
      }
      seg.received = existing;
    }
  }

  /// Verifies the remote file is still the one we started downloading.
  Future<void> _validateRemote() async {
    final pr = await _probe();
    var changed = false;
    if (task.etag != null && pr.etag != null && task.etag != pr.etag) {
      changed = true;
    } else if (task.lastModified != null &&
        pr.lastModified != null &&
        task.lastModified != pr.lastModified) {
      changed = true;
    }
    if (task.totalBytes > 0 && pr.totalBytes > 0 && task.totalBytes != pr.totalBytes) {
      changed = true;
    }
    if (changed) {
      throw const DownloadFailure(DownloadErrorCode.changed, needsRestart: true);
    }
    if (task.rangeSupported && !pr.rangeSupported) {
      throw const DownloadFailure(DownloadErrorCode.rangeIgnored, needsRestart: true);
    }
  }

  Future<void> _downloadSegment(int index) async {
    final seg = task.segments[index];
    final part = File(partFileName(partsDir, index));
    final uri = parseDownloadUri(task.url);

    final client = createHttpClient(
      connectTimeout: config.connectTimeout,
      proxy: config.proxy,
    );
    _clients.add(client);

    IOSink? sink;
    try {
      final from = seg.start + seg.received;
      final opened = await openGet(
        client,
        uri,
        headers: task.headers,
        secrets: task.secretHeaders,
        range: task.rangeSupported
            ? 'bytes=$from-${seg.end >= 0 ? seg.end : ''}'
            : null,
        timeout: config.readTimeout,
      );
      final response = opened.response;
      _check();

      final status = response.statusCode;
      if (task.rangeSupported && from > 0) {
        if (status == 200) {
          throw const DownloadFailure(DownloadErrorCode.rangeIgnored, needsRestart: true);
        }
        if (status != 206) throw DownloadFailure.status(status);
      } else if (status != 200 && status != 206) {
        throw DownloadFailure.status(status);
      }

      // Truncate stale data if we are (re)starting a segment from zero.
      sink = part.openWrite(
        mode: seg.received == 0 ? FileMode.write : FileMode.append,
      );

      var sinceFlush = 0;
      await for (final chunk in response.timeout(config.readTimeout)) {
        if (_stopped) break;
        var data = chunk;
        if (seg.end >= 0) {
          final remaining = seg.length - seg.received;
          if (remaining <= 0) break;
          if (data.length > remaining) data = data.sublist(0, remaining);
        }
        sink.add(data);
        seg.received += data.length;
        _tickBytes += data.length;
        sinceFlush += data.length;
        if (sinceFlush >= 1024 * 1024) {
          await sink.flush(); // bounded memory: never buffer more than ~1 MiB
          sinceFlush = 0;
        }
        await _throttle(data.length);
      }
      _check();

      if (seg.end >= 0 && seg.received < seg.length) {
        throw const DownloadFailure(DownloadErrorCode.incomplete, retryable: true);
      }
    } finally {
      if (sink != null) {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
      client.close(force: true);
      _clients.remove(client);
    }
  }

  Future<void> _throttle(int bytes) async {
    final limit = config.speedLimitBps;
    if (limit <= 0) return;
    _throttledBytes += bytes;
    final shouldHaveTaken = _throttledBytes * 1000000 ~/ limit; // microseconds
    final elapsed = _clock.elapsedMicroseconds;
    if (shouldHaveTaken > elapsed) {
      await Future<void>.delayed(Duration(microseconds: shouldHaveTaken - elapsed));
    }
  }

  /// Verifies every part, merges into a temp file next to the destination,
  /// checks the final size, then atomically renames into place.
  Future<void> _finalize() async {
    for (var i = 0; i < task.segments.length; i++) {
      final seg = task.segments[i];
      final f = File(partFileName(partsDir, i));
      final len = await f.exists() ? await f.length() : -1;
      if (len != seg.length) {
        throw const DownloadFailure(DownloadErrorCode.incomplete, retryable: true);
      }
    }

    final dir = task.directory;
    final finalPath = uniquePath(dir, sanitizeFileName(task.fileName));
    if (!isInside(dir, finalPath)) {
      throw const DownloadFailure(DownloadErrorCode.write);
    }
    final tmpPath = '$finalPath.zapdl-part';
    final tmp = File(tmpPath);

    if (task.segments.length == 1) {
      final part = File(partFileName(partsDir, 0));
      try {
        await part.rename(tmpPath);
      } on FileSystemException {
        await part.copy(tmpPath); // different volume
      }
    } else {
      final out = tmp.openWrite();
      try {
        for (var i = 0; i < task.segments.length; i++) {
          await out.addStream(File(partFileName(partsDir, i)).openRead());
        }
      } finally {
        await out.close();
      }
    }

    if (task.totalBytes > 0 && await tmp.length() != task.totalBytes) {
      await tmp.delete();
      throw const DownloadFailure(DownloadErrorCode.incomplete, retryable: true);
    }

    await tmp.rename(finalPath);
    task.fileName = p.basename(finalPath);
    try {
      await Directory(partsDir).delete(recursive: true);
    } catch (_) {}
  }
}
