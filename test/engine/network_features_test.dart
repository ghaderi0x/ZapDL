import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zapdl/engine/cookies.dart';
import 'package:zapdl/engine/engine.dart';
import 'package:zapdl/engine/errors.dart';
import 'package:zapdl/engine/http_support.dart';
import 'package:zapdl/engine/models.dart';
import 'package:zapdl/engine/store.dart';

/// Small origin server that records the headers of every request it sees and
/// can redirect. Supports Range so segmented downloads work.
class Origin {
  Origin(this.data);

  final Uint8List data;
  final List<Map<String, String>> seen = [];
  String? redirectTo;
  int delayPerChunkMs = 0;
  int chunkSize = 64 * 1024;
  late HttpServer _s;

  String get base => 'http://127.0.0.1:${_s.port}';
  String get url => '$base/file.bin';

  Future<void> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((req) => _handle(req).catchError((Object _) {}));
  }

  Future<void> stop() => _s.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final h = <String, String>{};
    req.headers.forEach((k, v) => h[k.toLowerCase()] = v.join(','));
    seen.add(h);
    final res = req.response;
    if (redirectTo != null) {
      res.statusCode = 302;
      res.headers.set(HttpHeaders.locationHeader, redirectTo!);
      await res.close();
      return;
    }
    var start = 0;
    var end = data.length - 1;
    var partial = false;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (m != null) {
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        if (end >= data.length) end = data.length - 1;
        partial = true;
      }
    }
    final length = end - start + 1;
    res.headers.set(HttpHeaders.etagHeader, '"v1"');
    res.headers.contentType = ContentType.binary;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (partial) {
      res.statusCode = 206;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${data.length}');
    }
    res.contentLength = length;
    var sent = 0;
    while (sent < length) {
      final n = chunkSize < length - sent ? chunkSize : length - sent;
      res.add(Uint8List.sublistView(data, start + sent, start + sent + n));
      sent += n;
      if (delayPerChunkMs > 0) {
        await res.flush();
        await Future<void>.delayed(Duration(milliseconds: delayPerChunkMs));
      }
    }
    await res.close();
  }
}

/// Behaves like an HTTP proxy for plain-HTTP requests: it answers every
/// request itself and records what it was asked for.
class FakeProxy {
  final List<Map<String, String>> seen = [];
  final List<String> targets = [];
  late HttpServer _s;
  int get port => _s.port;

  Future<void> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((req) async {
      final h = <String, String>{};
      req.headers.forEach((k, v) => h[k.toLowerCase()] = v.join(','));
      seen.add(h);
      targets.add(req.uri.toString());
      final body = utf8.encode('via-proxy');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.binary
        ..contentLength = body.length
        ..add(body);
      await req.response.close();
    });
  }

  Future<void> stop() => _s.close(force: true);
}

Uint8List makeData(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + i ~/ 251) & 0xFF));

String sha(List<int> b) => sha256.convert(b).toString();

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
  throw TimeoutException('Timed out; last: ${last?.status} ${last?.receivedBytes} ${last?.errorCode}');
}

void main() {
  late Directory root;
  late Directory outDir;
  late Origin origin;
  late Uint8List data;
  final engines = <DownloadEngine>[];

  DownloadEngine makeEngine({
    DownloadStore? store,
    SecretStore? secrets,
    DateTime Function()? clock,
    EngineConfig? config,
  }) {
    final e = DownloadEngine(
      store: store ?? InMemoryDownloadStore(),
      partsRoot: p.join(root.path, 'parts'),
      tickInterval: const Duration(milliseconds: 30),
      secrets: secrets,
      clock: clock,
      config: config ??
          EngineConfig(
            connections: 4,
            minSegmentBytes: 256 * 1024,
            maxRetries: 1,
            retryBackoffUnit: const Duration(milliseconds: 10),
            readTimeout: const Duration(seconds: 5),
          ),
    );
    engines.add(e);
    return e;
  }

  Future<List<int>> readOut(DownloadTask t) =>
      File(p.join(outDir.path, t.fileName)).readAsBytes();

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('zapdl_net');
    outDir = Directory(p.join(root.path, 'out'));
    data = makeData(2 * 1024 * 1024 + 77);
    origin = Origin(data);
    await origin.start();
  });

  tearDown(() async {
    for (final e in engines) {
      await e.shutdown();
    }
    engines.clear();
    await origin.stop();
    await root.delete(recursive: true);
  });

  group('headers, cookies and credentials', () {
    test('custom headers and cookies are sent; credentials never reach the JSON store',
        () async {
      final storeFile = File(p.join(root.path, 'downloads.json'));
      final e = makeEngine(store: JsonFileDownloadStore(storeFile));
      await e.init();
      final t = await e.add(
        url: origin.url,
        directory: outDir.path,
        headers: {'Referer': 'https://ref.example/', 'User-Agent': 'TestAgent/1'},
        cookies: 'session=SECRETCOOKIE; theme=dark',
      );
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(sha(await readOut(done)), sha(data));

      for (final h in origin.seen) {
        expect(h['referer'], 'https://ref.example/');
        expect(h['user-agent'], 'TestAgent/1');
        expect(h['cookie'], 'session=SECRETCOOKIE; theme=dark');
      }
      await e.shutdown();
      final json = await storeFile.readAsString();
      expect(json, contains('ref.example')); // plain headers are stored
      expect(json, isNot(contains('SECRETCOOKIE')));
    });

    test('user:password in the URL becomes a Basic header and is not stored', () async {
      final e = makeEngine();
      await e.init();
      final t = await e.add(
        url: origin.url.replaceFirst('127.0.0.1', 'bob:hunter2@127.0.0.1'),
        directory: outDir.path,
      );
      expect(t.url, isNot(contains('hunter2')));
      expect(t.url, isNot(contains('@')));
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      final expected = 'Basic ${base64.encode(utf8.encode('bob:hunter2'))}';
      expect(origin.seen.every((h) => h['authorization'] == expected), isTrue);
    });

    test('credentials are not forwarded to another origin after a redirect', () async {
      final other = Origin(data);
      await other.start();
      addTearDown(other.stop);
      origin.redirectTo = other.url;

      final e = makeEngine();
      await e.init();
      final t = await e.add(
        url: origin.url,
        directory: outDir.path,
        headers: {'Authorization': 'Bearer TOKEN123', 'Referer': 'https://r/'},
        cookies: 'a=b',
      );
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(origin.seen, isNotEmpty);
      expect(origin.seen.first['authorization'], 'Bearer TOKEN123');
      expect(other.seen, isNotEmpty);
      for (final h in other.seen) {
        expect(h.containsKey('authorization'), isFalse);
        expect(h.containsKey('cookie'), isFalse);
        expect(h['referer'], 'https://r/'); // harmless headers still follow
      }
    });

    test('header injection and engine-controlled headers are rejected', () async {
      final e = makeEngine();
      await e.init();
      Future<void> expectInvalid(Map<String, String> h) async {
        await expectLater(
          e.add(url: origin.url, directory: outDir.path, headers: h),
          throwsA(isA<DownloadFailure>()
              .having((f) => f.code, 'code', DownloadErrorCode.invalidHeader)),
        );
      }

      await expectInvalid({'X-A': 'ok\r\nX-Evil: 1'});
      await expectInvalid({'Bad Name': 'v'});
      await expectInvalid({'Range': 'bytes=5-'});
      await expectInvalid({'Host': 'evil.example'});
      expect(origin.seen, isEmpty, reason: 'nothing may be sent for rejected requests');
    });

    test('secrets survive a restart through the secret store and are removed at the end',
        () async {
      final storeFile = File(p.join(root.path, 'downloads.json'));
      final secrets = InMemorySecretStore();
      origin
        ..chunkSize = 32 * 1024
        ..delayPerChunkMs = 15;

      final e1 = makeEngine(store: JsonFileDownloadStore(storeFile), secrets: secrets);
      await e1.init();
      final t = await e1.add(url: origin.url, directory: outDir.path, cookies: 'k=v');
      await waitFor(e1, t.id, (x) => x.receivedBytes > 200 * 1024);
      await e1.shutdown();
      expect(await secrets.read(t.id), {'Cookie': 'k=v'});

      origin
        ..delayPerChunkMs = 0
        ..seen.clear();
      final e2 = makeEngine(store: JsonFileDownloadStore(storeFile), secrets: secrets);
      await e2.init();
      expect(e2.snapshot.single.secretHeaders['Cookie'], 'k=v');
      await e2.resume(t.id);
      final done = await waitFor(e2, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(origin.seen.every((h) => h['cookie'] == 'k=v'), isTrue);
      expect(await secrets.read(t.id), isEmpty, reason: 'deleted once finished');
    });
  });

  group('cookies.txt', () {
    const file = '# Netscape HTTP Cookie File\n'
        '.example.com\tTRUE\t/\tFALSE\t0\tsid\tabc\n'
        '#HttpOnly_.example.com\tTRUE\t/private\tTRUE\t0\ttok\tsecret\n'
        'www.other.com\tFALSE\t/\tFALSE\t0\tx\ty\n'
        '.example.com\tTRUE\t/\tFALSE\t1000\told\tgone\n';

    test('matches domain, path, Secure and expiry', () {
      final cookies = parseNetscapeCookies(file);
      expect(cookies, hasLength(4));
      final now = DateTime.utc(2026, 1, 1);
      expect(
        cookieHeaderFor(Uri.parse('http://a.example.com/x'), cookies, now: now),
        'sid=abc',
      );
      expect(
        cookieHeaderFor(Uri.parse('https://example.com/private/f'), cookies, now: now),
        'sid=abc; tok=secret',
      );
      expect(
        cookieHeaderFor(Uri.parse('http://example.com/private/f'), cookies, now: now),
        'sid=abc',
        reason: 'Secure cookies are not sent over http',
      );
      expect(cookieHeaderFor(Uri.parse('http://notexample.com/'), cookies, now: now), isNull);
      expect(cookieHeaderFor(Uri.parse('http://sub.other.com/'), cookies, now: now), isNull);
      expect(cookieHeaderFor(Uri.parse('http://www.other.com/'), cookies, now: now), 'x=y');
    });

    test('raw cookie strings pass through; newlines are rejected', () {
      final u = Uri.parse('https://example.com/');
      expect(cookieHeaderFromInput('Cookie: a=b; c=d', u), 'a=b; c=d');
      expect(cookieHeaderFromInput('   ', u), isNull);
      expect(() => cookieHeaderFromInput('a=b\nX: y', u), throwsA(isA<DownloadFailure>()));
    });
  });

  group('proxy', () {
    test('manual HTTP proxy carries the request, with credentials', () async {
      final proxy = FakeProxy();
      await proxy.start();
      addTearDown(proxy.stop);
      final e = makeEngine(
        config: EngineConfig(
          proxy: ProxyConfig(
            mode: ProxyMode.manual,
            host: '127.0.0.1',
            port: proxy.port,
            username: 'u',
            password: 'pw',
          ),
          maxRetries: 0,
        ),
      );
      await e.init();
      final t = await e.add(url: 'http://files.invalid/hello.txt', directory: outDir.path);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(utf8.decode(await readOut(done)), 'via-proxy');
      expect(proxy.targets, isNotEmpty);
      expect(proxy.targets.every((u) => u.contains('files.invalid')), isTrue);
      expect(
        proxy.seen.first['proxy-authorization'],
        'Basic ${base64.encode(utf8.encode('u:pw'))}',
      );
    });

    test('an invalid manual proxy fails with a proxy error', () async {
      final e = makeEngine(
        config: EngineConfig(
          proxy: const ProxyConfig(mode: ProxyMode.manual, host: 'bad host', port: 8080),
        ),
      );
      await e.init();
      await expectLater(
        e.add(url: origin.url, directory: outDir.path),
        throwsA(isA<DownloadFailure>()
            .having((f) => f.code, 'code', DownloadErrorCode.proxy)),
      );
    });

    test('proxy validation rules', () {
      expect(const ProxyConfig(mode: ProxyMode.manual, host: 'p.example', port: 3128).isManualValid,
          isTrue);
      expect(const ProxyConfig(mode: ProxyMode.manual, host: '', port: 3128).isManualValid, isFalse);
      expect(const ProxyConfig(mode: ProxyMode.manual, host: 'p', port: 70000).isManualValid,
          isFalse);
      expect(const ProxyConfig(mode: ProxyMode.manual, host: 'a@b', port: 1).isManualValid, isFalse);
    });
  });

  group('gates: Wi-Fi only, schedule window, scheduled start, suspend', () {
    test('network gate holds downloads and releases them', () async {
      final e = makeEngine();
      await e.init();
      e.setNetworkAllowed(false);
      expect(e.gate, EngineGate.network);
      final t = await e.add(url: origin.url, directory: outDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      var s = e.snapshot.single;
      expect(s.status, DownloadStatus.queued);
      expect(s.receivedBytes, 0);
      expect(origin.seen.length, 1, reason: 'only the probe may have been sent');

      e.setNetworkAllowed(true);
      expect(e.gate, EngineGate.open);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(sha(await readOut(done)), sha(data));
    });

    test('losing the network mid-download queues it and it finishes intact', () async {
      origin
        ..chunkSize = 32 * 1024
        ..delayPerChunkMs = 15;
      final e = makeEngine();
      await e.init();
      final t = await e.add(url: origin.url, directory: outDir.path);
      await waitFor(e, t.id, (x) => x.receivedBytes > 200 * 1024);
      e.setNetworkAllowed(false);
      var s = await waitFor(e, t.id, (x) => x.status == DownloadStatus.queued);
      expect(s.speedBps, 0);
      final before = origin.seen.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(origin.seen.length, before, reason: 'no new requests while gated');

      origin.delayPerChunkMs = 0;
      e.setNetworkAllowed(true);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(sha(await readOut(done)), sha(data));
    });

    test('suspend / unsuspend resumes automatically', () async {
      origin
        ..chunkSize = 32 * 1024
        ..delayPerChunkMs = 15;
      final e = makeEngine();
      await e.init();
      final t = await e.add(url: origin.url, directory: outDir.path);
      await waitFor(e, t.id, (x) => x.receivedBytes > 100 * 1024);
      e.setSuspended(true);
      expect(e.gate, EngineGate.suspended);
      await waitFor(e, t.id, (x) => x.status == DownloadStatus.queued);
      origin.delayPerChunkMs = 0;
      e.setSuspended(false);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(sha(await readOut(done)), sha(data));
    });

    test('daily window: downloads only run inside it (window spans midnight)', () async {
      var now = DateTime(2026, 1, 1, 12, 0);
      final e = makeEngine(
        clock: () => now,
        config: EngineConfig(
          minSegmentBytes: 256 * 1024,
          allowedWindow: const DailyWindow(startMinute: 23 * 60, endMinute: 6 * 60),
        ),
      );
      await e.init();
      expect(e.gate, EngineGate.schedule);
      final t = await e.add(url: origin.url, directory: outDir.path);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(e.snapshot.single.status, DownloadStatus.queued);

      now = DateTime(2026, 1, 1, 23, 30);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(e.gate, EngineGate.open);
    });

    test('a scheduled download waits for its start time and then clears it', () async {
      var now = DateTime(2026, 1, 1, 8, 0);
      final e = makeEngine(clock: () => now);
      await e.init();
      final t = await e.add(
        url: origin.url,
        directory: outDir.path,
        scheduledAt: DateTime(2026, 1, 1, 9, 0),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      var s = e.snapshot.single;
      expect(s.status, DownloadStatus.queued);
      expect(s.scheduledAt, isNotNull);
      expect(origin.seen.length, 1, reason: 'only the probe before the start time');

      now = DateTime(2026, 1, 1, 9, 0, 1);
      final done = await waitFor(e, t.id, (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(done.scheduledAt, isNull);
    });

    test('the schedule survives a restart', () async {
      final storeFile = File(p.join(root.path, 'downloads.json'));
      final when = DateTime(2030, 5, 5, 5, 5);
      final e1 = makeEngine(store: JsonFileDownloadStore(storeFile));
      await e1.init();
      await e1.add(url: origin.url, directory: outDir.path, scheduledAt: when);
      await e1.shutdown(keepQueued: true);
      final e2 = makeEngine(store: JsonFileDownloadStore(storeFile));
      await e2.init();
      final s = e2.snapshot.single;
      expect(s.scheduledAt, when);
      expect(s.status, DownloadStatus.queued);
    });

    test('retryNetworkFailures re-queues only network failures', () async {
      final store = InMemoryDownloadStore()
        ..saved = [
          DownloadTask(
              id: 'a',
              url: 'http://x.invalid/a',
              fileName: 'a',
              directory: outDir.path,
              status: DownloadStatus.failed,
              errorCode: DownloadErrorCode.network),
          DownloadTask(
              id: 'b',
              url: 'http://x.invalid/b',
              fileName: 'b',
              directory: outDir.path,
              status: DownloadStatus.failed,
              errorCode: DownloadErrorCode.notFound),
        ];
      final e = makeEngine(store: store);
      await e.init();
      e.setNetworkAllowed(false); // keep the re-queued task from starting
      expect(e.retryNetworkFailures(), 1);
      final byId = {for (final t in e.snapshot) t.id: t};
      expect(byId['a']!.status, DownloadStatus.queued);
      expect(byId['b']!.status, DownloadStatus.failed);
    });

    test('init(resumeInterrupted) re-queues downloads that were running', () async {
      final store = InMemoryDownloadStore()
        ..saved = [
          DownloadTask(
              id: 'r',
              url: origin.url,
              fileName: 'file.bin',
              directory: outDir.path,
              status: DownloadStatus.downloading),
        ];
      final e = makeEngine(store: store);
      e.config.proxy = const ProxyConfig(mode: ProxyMode.none);
      await e.init(resumeInterrupted: true);
      final done = await waitFor(e, 'r', (x) => x.isFinished);
      expect(done.status, DownloadStatus.completed);
      expect(sha(await readOut(done)), sha(data));
    });
  });

  group('DailyWindow', () {
    test('same-day and overnight windows', () {
      const day = DailyWindow(startMinute: 9 * 60, endMinute: 17 * 60);
      expect(day.contains(DateTime(2026, 1, 1, 9, 0)), isTrue);
      expect(day.contains(DateTime(2026, 1, 1, 16, 59)), isTrue);
      expect(day.contains(DateTime(2026, 1, 1, 17, 0)), isFalse);
      const night = DailyWindow(startMinute: 23 * 60, endMinute: 6 * 60);
      expect(night.contains(DateTime(2026, 1, 1, 23, 0)), isTrue);
      expect(night.contains(DateTime(2026, 1, 2, 5, 59)), isTrue);
      expect(night.contains(DateTime(2026, 1, 2, 6, 0)), isFalse);
      expect(night.contains(DateTime(2026, 1, 2, 12, 0)), isFalse);
      const always = DailyWindow(startMinute: 0, endMinute: 0);
      expect(always.contains(DateTime(2026, 1, 1, 3, 3)), isTrue);
    });
  });
}
