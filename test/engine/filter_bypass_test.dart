import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/engine/filter_bypass.dart';

class _FixedResolver extends DohResolver {
  _FixedResolver(this.ip);
  final String ip;
  @override
  Future<List<InternetAddress>> resolve(String host) async => [InternetAddress(ip)];
}

void main() {
  test('parseDohJson keeps only IPv4 A records', () {
    const body = '{"Status":0,"Answer":['
        '{"name":"a.com","type":5,"data":"b.com."},'
        '{"name":"b.com","type":1,"data":"93.184.216.34"},'
        '{"name":"b.com","type":28,"data":"2606::1"}]}';
    expect(parseDohJson(body), ['93.184.216.34']);
  });

  test('parseDohJson is safe on bad input', () {
    expect(parseDohJson('not json'), isEmpty);
    expect(parseDohJson('{"Status":3}'), isEmpty);
    expect(parseDohJson('{"Status":0}'), isEmpty);
  });

  test('splitHandshake splits TLS hellos and keeps the bytes', () {
    final data = Uint8List.fromList([0x16, 0x03, 0x01, ...List.generate(400, (i) => i % 256)]);
    final parts = splitHandshake(data, random: Random(1));
    expect(parts.length, greaterThan(3));
    expect(parts.expand((e) => e).toList(), data);
    expect(parts.every((p) => p.length <= 100), isTrue);
  });

  test('splitHandshake leaves other data alone', () {
    final data = Uint8List.fromList(List.filled(300, 0x41));
    expect(splitHandshake(data), hasLength(1));
  });

  test('forUri is direct while stopped', () {
    expect(FilterBypass.forUri(Uri.parse('https://example.com')), 'DIRECT');
  });

  test('proxy tunnels bytes to the resolved address', () async {
    final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <int>[];
    echo.listen((s) {
      s.listen((d) {
        received.addAll(d);
        s.add(d);
      });
    });
    await FilterBypass.start(resolver: _FixedResolver('127.0.0.1'));
    addTearDown(() async {
      await FilterBypass.stop();
      await echo.close();
    });
    expect(FilterBypass.forUri(Uri.parse('https://x.test')), startsWith('PROXY 127.0.0.1:'));

    final c = await Socket.connect(InternetAddress.loopbackIPv4, FilterBypass.port!);
    final reply = StringBuffer();
    final got = Completer<List<int>>();
    final buf = <int>[];
    c.listen((d) {
      buf.addAll(d);
      final text = latin1.decode(buf);
      if (text.contains('\r\n\r\n') && !reply.isNotEmpty) reply.write('ok');
      final hello = [0x16, 0x03, 0x01, ...List.filled(250, 7)];
      if (reply.isNotEmpty && !got.isCompleted && buf.length >= 39 + hello.length) {
        got.complete(buf);
      }
    });
    c.add(ascii.encode('CONNECT x.test:${echo.port} HTTP/1.1\r\nHost: x.test\r\n\r\n'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final hello = [0x16, 0x03, 0x01, ...List.filled(250, 7)];
    c.add(hello);
    final all = await got.future.timeout(const Duration(seconds: 5));
    expect(latin1.decode(all.sublist(0, 12)), 'HTTP/1.1 200');
    expect(all.sublist(all.length - hello.length), hello);
    expect(received, hello);
    await c.close();
  });
}
