import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/engine/parts.dart';
import 'package:zapdl/engine/system_proxy.dart';

void main() {
  group('nextPartUrl', () {
    test('partN names', () {
      expect(nextPartUrl('https://x.com/a/game.part1.zip'), 'https://x.com/a/game.part2.zip');
      expect(nextPartUrl('https://x.com/game.part09.rar'), 'https://x.com/game.part10.rar');
      expect(nextPartUrl('https://x.com/game2.part3.rar'), 'https://x.com/game2.part4.rar');
      expect(nextPartUrl('https://x.com/Game-Part-7.zip'), 'https://x.com/Game-Part-8.zip');
    });

    test('numeric extensions and z01 splits', () {
      expect(nextPartUrl('https://x.com/data.001'), 'https://x.com/data.002');
      expect(nextPartUrl('https://x.com/data.zip.099'), 'https://x.com/data.zip.100');
      expect(nextPartUrl('https://x.com/a.z01'), 'https://x.com/a.z02');
    });

    test('keeps the query string', () {
      expect(nextPartUrl('https://x.com/f.part1.rar?token=abc'),
          'https://x.com/f.part2.rar?token=abc');
    });

    test('plain files are not parts', () {
      expect(nextPartUrl('https://x.com/movie.mp4'), isNull);
      expect(looksLikePart('https://x.com/movie.mp4'), isFalse);
      expect(looksLikePart('https://x.com/g.part1.zip'), isTrue);
      expect(nextPartUrl('https://x.com/'), isNull);
    });
  });

  group('SystemProxy.parseProxyServer', () {
    test('host:port', () {
      expect(SystemProxy.parseProxyServer('127.0.0.1:10809'), (host: '127.0.0.1', port: 10809));
    });

    test('per-protocol list prefers https, then http, ignores socks', () {
      expect(SystemProxy.parseProxyServer('http=a:1;https=b:2;socks=c:3'), (host: 'b', port: 2));
      expect(SystemProxy.parseProxyServer('socks=c:3'), isNull);
    });

    test('scheme prefix and garbage', () {
      expect(SystemProxy.parseProxyServer('http://h:8080'), (host: 'h', port: 8080));
      expect(SystemProxy.parseProxyServer('nonsense'), isNull);
      expect(SystemProxy.parseProxyServer('h:99999'), isNull);
    });
  });
}
