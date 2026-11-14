import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zapdl/engine/engine.dart';
import 'package:zapdl/engine/errors.dart';
import 'package:zapdl/engine/models.dart';
import 'package:zapdl/engine/store.dart';

/// Local HTTP server that behaves like a real file host (Range, ETag) and can
/// misbehave on purpose. The engine under test talks to it over real sockets.
class TestServer {
  TestServer(this.data);

  Uint8List data;
  bool ranges = true;
  String etag = '"v1"';
  int chunkSize = 64 * 1024;
  int delayPerChunkMs = 0;
  int? forceStatus;

  /// Number of upcoming bulk (non-probe) requests to cut short.
  int cutRequests = 0;
  int cutAfterBytes = 100 * 1024;

  int bulkRequests = 0;
  late HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}/file.bin';
  String get missingUrl => 'http://127.0.0.1:${_server.port}/missing';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) => _handle(req).catchError((Object _) {}));
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    if (req.uri.path == '/missing') {
      res.statusCode = 404;
      await res.close();
      return;
    }
    if (forceStatus != null) {
      res.statusCode = forceStatus!;
      await res.close();
      return;
    }

    var start = 0;
    var end = data.length - 1;
    var partial = false;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (ranges && range != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (m != null) {
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        if (end >= data.length) end = data.length - 1;
        partial = true;
      }
    }
    final length = end - start + 1;
    final isProbe = length <= 1;
    if (!isProbe) bulkRequests++;

    res.headers.set(HttpHeaders.etagHeader, etag);
    res.headers.set(HttpHeaders.lastModifiedHeader, 'Wed, 01 Jan 2025 00:00:00 GMT');
    res.headers.contentType = ContentType.binary;
    if (ranges) res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (partial) {
      res.statusCode = 206;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
    }
    res.contentLength = length;

    final cut = !isProbe && cutRequests > 0;
    if (cut) cutRequests--;

    var sent = 0;
    while (sent < length) {
      final n = chunkSize < length - sent ? chunkSize : length - sent;
      res.add(Uint8List.sublistView(data, start + sent, start + sent + n));
      sent += n;
      if (cut && sent >= cutAfterBytes) {
        await res.flush();
        final socket = await res.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      if (delayPerChunkMs > 0) {
        await res.flush();
        await Future<void>.delayed(Duration(milliseconds: delayPerChunkMs));
      }
    }
    await res.close();
  }
}

Uint8List makeData(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + i ~/ 251) & 0xFF));

String sha(List<int> bytes) => sha256.convert(bytes).toString();

Future<DownloadTask> waitFor(
  DownloadEngine e,
  String id,
  bool Function(DownloadTask) test, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  DownloadTask? last;
  while (DateTime.now().isBefore(end)) {
    last = e.snapshot.firstWhere((t) => t.id == id);
    if (test(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException(
    'Timed out; last state: ${last?.status} ${last?.receivedBytes}/${last?.totalBytes} ${last?.errorCode}',
  );
}

void main() {
  late Directory root;
  late Directory outDir;
  late TestServer server;
  late Uint8List data;
  final engines = <DownloadEngine>[];

  DownloadEngine makeEngine({DownloadStore? store, int maxConcurrent = 3}) {
    final e = DownloadEngine(
      store: store ?? InMemoryDownloadStore(),
      partsRoot: p.join(root.path, 'parts'),
      tickInterval: const Duration(milliseconds: 30),
      config: EngineConfig(
        maxConcurrent: maxConcurrent,
        connections: 4,
        minSegmentBytes: 256 * 1024,
        maxRetries: 2,
        retryBackoffUnit: const Duration(milliseconds: 10),
        readTimeout: const Duration(seconds: 5),
      ),
    );
    engines.add(e);
    return e;
  }

  setUpAll(() {
    // Flutter's test binding can replace HttpClient; make sure we use the real one.
    HttpOverrides.global = null;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zapdl_engine');
    outDir = Directory(p.join(root.path, 'out'));
    data = makeData(3 * 1024 * 1024 + 123);
    server = TestServer(data);
    await server.start();
  });

  tearDown(() async {
    for (final e in engines) {
      await e.shutdown();
    }
    engines.clear();
    await server.stop();
    await root.delete(recursive: true);
  });

  Future<List<int>> readOut(DownloadTask t) =>
      File(p.join(outDir.path, t.fileName)).readAsBytes();

  test('segmented download produces a byte-identical file', () async {
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    expect(t.rangeSupported, isTrue);
    expect(t.segments.length, greaterThan(1), reason: 'should use multiple connections');
    expect(t.fileName, 'file.bin');

    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(done.receivedBytes, data.length);
    expect(sha(await readOut(done)), sha(data));
    // Temporary parts are cleaned up and no stray temp file is left behind.
    expect(Directory(p.join(root.path, 'parts', t.id)).existsSync(), isFalse);
    expect(
      outDir.listSync().whereType<File>().map((f) => p.basename(f.path)),
      ['file.bin'],
    );
  });

  test('falls back to a single connection when ranges are unsupported', () async {
    server.ranges = false;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    expect(t.rangeSupported, isFalse);
    expect(t.segments.length, 1);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(data));
  });

  test('honors a custom (and sanitized) file name', () async {
    final e = makeEngine();
    await e.init();
    final t = await e.add(
      url: server.url,
      directory: outDir.path,
      fileName: '../../evil/name.bin',
    );
    expect(t.fileName, 'name.bin');
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(File(p.join(outDir.path, 'name.bin')).existsSync(), isTrue);
  });

  test('does not overwrite an existing file', () async {
    await outDir.create(recursive: true);
    await File(p.join(outDir.path, 'file.bin')).writeAsString('precious');
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(done.fileName, 'file (1).bin');
    expect(await File(p.join(outDir.path, 'file.bin')).readAsString(), 'precious');
  });

  test('adding a missing URL fails with notFound', () async {
    final e = makeEngine();
    await e.init();
    await expectLater(
      e.add(url: server.missingUrl, directory: outDir.path),
      throwsA(isA<DownloadFailure>()
          .having((f) => f.code, 'code', DownloadErrorCode.notFound)),
    );
    expect(e.snapshot, isEmpty);
  });

  test('link that expires after probing fails as accessDenied, never completes', () async {
    final e = makeEngine();
    await e.init();
    final probe = await e.probe(server.url);
    server.forceStatus = 403;
    final t = await e.add(url: server.url, directory: outDir.path, probe: probe);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.failed);
    expect(done.errorCode, DownloadErrorCode.accessDenied);
    expect(File(p.join(outDir.path, 'file.bin')).existsSync(), isFalse);
  });

  test('pause keeps partial data and resume completes correctly', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 15;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);

    await waitFor(e, t.id, (x) => x.receivedBytes > 300 * 1024);
    e.pause(t.id);
    final paused = await waitFor(e, t.id, (x) => x.status == DownloadStatus.paused);
    expect(paused.receivedBytes, lessThan(data.length));
    expect(File(p.join(outDir.path, 'file.bin')).existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final stillPaused = e.snapshot.single;
    expect(stillPaused.status, DownloadStatus.paused);

    server.delayPerChunkMs = 0;
    await e.resume(t.id);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(data));
  });

  test('resume refuses when the remote file changed, retry restarts cleanly', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 15;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    await waitFor(e, t.id, (x) => x.receivedBytes > 300 * 1024);
    e.pause(t.id);
    await waitFor(e, t.id, (x) => x.status == DownloadStatus.paused);

    // Remote file is replaced by different content with a new ETag.
    final newData = makeData(data.length)..[0] = 0xAB;
    server
      ..data = newData
      ..etag = '"v2"'
      ..delayPerChunkMs = 0;

    await e.resume(t.id);
    final failed = await waitFor(e, t.id, (x) => x.isFinished);
    expect(failed.status, DownloadStatus.failed);
    expect(failed.errorCode, DownloadErrorCode.changed);
    expect(failed.needsRestart, isTrue);
    expect(File(p.join(outDir.path, 'file.bin')).existsSync(), isFalse);

    await e.resume(t.id); // user taps Retry
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(newData));
  });

  test('connection dropped mid-transfer is retried and resumed without corruption', () async {
    server.cutRequests = 1;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(data));
  });

  test('persistent truncation fails and is never marked completed', () async {
    server
      ..cutRequests = 1000
      ..cutAfterBytes = 64 * 1024;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.failed);
    expect(
      done.errorCode,
      anyOf(DownloadErrorCode.incomplete, DownloadErrorCode.network, DownloadErrorCode.timeout),
    );
    expect(File(p.join(outDir.path, 'file.bin')).existsSync(), isFalse);
  });

  test('state survives an app restart and the download can be finished', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 15;
    final storeFile = File(p.join(root.path, 'downloads.json'));

    final e1 = makeEngine(store: JsonFileDownloadStore(storeFile));
    await e1.init();
    final t = await e1.add(url: server.url, directory: outDir.path);
    await waitFor(e1, t.id, (x) => x.receivedBytes > 300 * 1024);
    await e1.shutdown(); // simulates closing the app

    server.delayPerChunkMs = 0;
    final e2 = makeEngine(store: JsonFileDownloadStore(storeFile));
    await e2.init();
    final restored = e2.snapshot.single;
    expect(restored.id, t.id);
    expect(restored.status, DownloadStatus.paused);
    expect(restored.receivedBytes, greaterThan(0));
    expect(restored.segments, isNotEmpty);

    await e2.resume(t.id);
    final done = await waitFor(e2, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(data));
  });

  test('respects the concurrent download limit', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 5;
    final e = makeEngine(maxConcurrent: 1);
    await e.init();
    final a = await e.add(url: server.url, directory: outDir.path, fileName: 'a.bin');
    final b = await e.add(url: server.url, directory: outDir.path, fileName: 'b.bin');

    var maxActive = 0;
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(end)) {
      final snap = e.snapshot;
      final active = snap.where((t) => t.status == DownloadStatus.downloading).length;
      if (active > maxActive) maxActive = active;
      if (snap.every((t) => t.status == DownloadStatus.completed)) break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(maxActive, 1);
    expect(e.snapshot.every((t) => t.status == DownloadStatus.completed), isTrue);
    expect(sha(await readOut(e.snapshot.firstWhere((t) => t.id == a.id))), sha(data));
    expect(sha(await readOut(e.snapshot.firstWhere((t) => t.id == b.id))), sha(data));
  });

  test('cleanOrphanedParts removes unreferenced folders but keeps live ones', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 15;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    await waitFor(e, t.id, (x) => x.receivedBytes > 100 * 1024);

    final orphan = Directory(p.join(root.path, 'parts', 'orphan-id'));
    await orphan.create(recursive: true);
    await File(p.join(orphan.path, 'part0')).writeAsBytes(List.filled(100, 1));

    final freed = await e.cleanOrphanedParts();
    expect(freed, 100);
    expect(orphan.existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'parts', t.id)).existsSync(), isTrue,
        reason: 'parts of a running download must be kept');

    // Nothing left to clean.
    expect(await e.cleanOrphanedParts(), 0);

    server.delayPerChunkMs = 0;
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    expect(sha(await readOut(done)), sha(data));
  });

  test('cancel removes partial data; remove(deleteFile) deletes the file', () async {
    server
      ..chunkSize = 32 * 1024
      ..delayPerChunkMs = 15;
    final e = makeEngine();
    await e.init();
    final t = await e.add(url: server.url, directory: outDir.path);
    await waitFor(e, t.id, (x) => x.receivedBytes > 100 * 1024);
    await e.cancel(t.id);
    final canceled = e.snapshot.single;
    expect(canceled.status, DownloadStatus.canceled);
    expect(canceled.receivedBytes, 0);
    expect(Directory(p.join(root.path, 'parts', t.id)).existsSync(), isFalse);

    server.delayPerChunkMs = 0;
    await e.resume(t.id); // retry after cancel starts from scratch
    final done = await waitFor(e, t.id, (x) => x.isFinished);
    expect(done.status, DownloadStatus.completed);
    final path = p.join(outDir.path, done.fileName);
    expect(File(path).existsSync(), isTrue);

    await e.remove(t.id, deleteFile: true);
    expect(File(path).existsSync(), isFalse);
    expect(e.snapshot, isEmpty);
  });
}
