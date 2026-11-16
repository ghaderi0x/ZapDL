import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Helps reach sites that a national filter blocks by NAME (DNS poisoning and
/// reading the site name in the TLS handshake), with no VPN:
///
///  1. **Encrypted DNS (DoH)**: the real IP address is looked up over HTTPS to a
///     public resolver by IP, so a poisoned local DNS answer is never used.
///  2. **Handshake splitting**: the first message of a TLS connection (which
///     contains the site name) is sent in several small pieces with tiny pauses,
///     so filters that only look at single packets do not recognize it.
///
/// It runs as a small HTTP CONNECT proxy on 127.0.0.1 that the app's own HTTP
/// clients are pointed to. It cannot help when a site is blocked by its IP
/// address (some Telegram servers, for example), when the filter reassembles
/// packets, or on connections that are cut for other reasons. Whether it works
/// depends on the internet provider. Nothing is encrypted beyond what HTTPS
/// already does; it is not a VPN and hides nothing from your provider.
class FilterBypass {
  FilterBypass._();

  static _Proxy? _proxy;

  /// Local port while running, else null.
  static int? get port => _proxy?.port;

  static bool get running => _proxy != null;

  static Future<void> start({DohResolver? resolver}) async {
    if (_proxy != null) return;
    _proxy = await _Proxy.start(resolver ?? DohResolver());
  }

  static Future<void> stop() async {
    final p = _proxy;
    _proxy = null;
    await p?.close();
  }

  /// For `HttpClient.findProxy`: HTTPS goes through the local proxy while it
  /// runs; plain HTTP is not read by name-based filters and goes direct.
  static String forUri(Uri uri) {
    final p = port;
    if (p != null && uri.scheme == 'https' && !_isLocal(uri.host)) {
      return 'PROXY 127.0.0.1:$p';
    }
    return 'DIRECT';
  }

  static bool _isLocal(String h) => h == 'localhost' || h == '127.0.0.1' || h == '::1';
}

// ------------------------------------------------------------------- DoH

/// Parses a DNS-over-HTTPS JSON answer (Cloudflare / Google format) into IPv4
/// addresses. Records of other types (CNAME, AAAA) are ignored.
List<String> parseDohJson(String body) {
  try {
    final root = jsonDecode(body);
    if (root is! Map || (root['Status'] != null && root['Status'] != 0)) return const [];
    final answers = root['Answer'];
    if (answers is! List) return const [];
    return [
      for (final a in answers)
        if (a is Map && a['type'] == 1 && a['data'] is String && _isIPv4(a['data'] as String))
          a['data'] as String,
    ];
  } catch (_) {
    return const [];
  }
}

bool _isIPv4(String s) => InternetAddress.tryParse(s)?.type == InternetAddressType.IPv4;

/// Resolves host names over HTTPS to public resolvers addressed by IP.
class DohResolver {
  DohResolver({
    this.endpoints = const [
      'https://1.1.1.1/dns-query',
      'https://8.8.8.8/resolve',
      'https://1.0.0.1/dns-query',
    ],
    this.timeout = const Duration(seconds: 6),
    this.systemFallback = true,
  });

  final List<String> endpoints;
  final Duration timeout;

  /// Use the system resolver when every DoH server fails.
  final bool systemFallback;

  final Map<String, (List<InternetAddress>, DateTime)> _cache = {};

  Future<List<InternetAddress>> resolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal];

    final hit = _cache[host];
    if (hit != null && DateTime.now().difference(hit.$2) < const Duration(minutes: 5)) {
      return hit.$1;
    }
    for (final endpoint in endpoints) {
      final ips = await _query(endpoint, host);
      if (ips.isNotEmpty) {
        final result = [for (final ip in ips) InternetAddress(ip)];
        _cache[host] = (result, DateTime.now());
        return result;
      }
    }
    if (systemFallback) {
      try {
        final r = await InternetAddress.lookup(host, type: InternetAddressType.IPv4)
            .timeout(timeout);
        if (r.isNotEmpty) return r;
      } catch (_) {}
    }
    return const [];
  }

  Future<List<String>> _query(String endpoint, String host) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri.parse(endpoint).replace(queryParameters: {'name': host, 'type': 'A'});
      final req = await client.getUrl(uri).timeout(timeout);
      req.headers.set('accept', 'application/dns-json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return const [];
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      return parseDohJson(body);
    } catch (_) {
      return const [];
    } finally {
      client.close(force: true);
    }
  }
}

// ---------------------------------------------------------- Splitting

/// Splits the first TLS message into small pieces. Returns the data untouched
/// when it does not look like a TLS handshake (so other protocols are not
/// disturbed). Piece sizes are random between [minPiece] and [maxPiece].
List<Uint8List> splitHandshake(
  List<int> data, {
  int minPiece = 30,
  int maxPiece = 100,
  math.Random? random,
}) {
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  final isTlsHandshake = bytes.length > 5 && bytes[0] == 0x16 && bytes[1] == 0x03;
  if (!isTlsHandshake) return [bytes];
  final rnd = random ?? math.Random();
  final pieces = <Uint8List>[];
  var i = 0;
  while (i < bytes.length) {
    final size = minPiece + rnd.nextInt(maxPiece - minPiece + 1);
    final end = math.min(i + size, bytes.length);
    pieces.add(Uint8List.sublistView(bytes, i, end));
    i = end;
  }
  return pieces;
}

// ------------------------------------------------------------------ Proxy

class _Proxy {
  _Proxy._(this._server, this.resolver);

  final ServerSocket _server;
  final DohResolver resolver;
  final Set<Socket> _open = {};
  final _rnd = math.Random();

  int get port => _server.port;

  static Future<_Proxy> start(DohResolver resolver) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = _Proxy._(server, resolver);
    server.listen((c) => unawaited(p._handle(c)), onError: (_) {});
    return p;
  }

  Future<void> close() async {
    await _server.close();
    for (final s in _open.toList()) {
      s.destroy();
    }
    _open.clear();
  }

  void _track(Socket s) => _open.add(s);

  void _drop(Socket s) {
    _open.remove(s);
    s.destroy();
  }

  Future<void> _handle(Socket client) async {
    _track(client);
    Socket? upstream;
    try {
      client.setOption(SocketOption.tcpNoDelay, true);
      final it = StreamIterator<List<int>>(client);

      // 1) Read the CONNECT request line + headers.
      final head = <int>[];
      var leftover = <int>[];
      while (true) {
        if (!await it.moveNext().timeout(const Duration(seconds: 15))) {
          return;
        }
        head.addAll(it.current);
        final end = _headerEnd(head);
        if (end >= 0) {
          leftover = head.sublist(end);
          head.removeRange(end, head.length);
          break;
        }
        if (head.length > 16 * 1024) return;
      }
      final firstLine = ascii.decode(head, allowInvalid: true).split('\r\n').first;
      final m = RegExp(r'^CONNECT\s+(\[[^\]]+\]|[^:\s]+):(\d+)\s+HTTP/1\.[01]$')
          .firstMatch(firstLine);
      if (m == null) {
        client.add(ascii.encode('HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n'));
        await client.flush();
        return;
      }
      final host = m.group(1)!.replaceAll(RegExp(r'^\[|\]$'), '');
      final targetPort = int.parse(m.group(2)!);

      // 2) Resolve over DoH and connect.
      final ips = await resolver.resolve(host);
      for (final ip in ips) {
        try {
          upstream = await Socket.connect(ip, targetPort, timeout: const Duration(seconds: 10));
          break;
        } catch (_) {}
      }
      if (upstream == null) {
        client.add(ascii.encode('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n'));
        await client.flush();
        return;
      }
      final up = upstream;
      _track(up);
      up.setOption(SocketOption.tcpNoDelay, true);
      client.add(ascii.encode('HTTP/1.1 200 Connection Established\r\n\r\n'));
      await client.flush();

      // 3) Client -> server: the first message is split, the rest is piped.
      Future<void> upstreamPump() async {
        List<int>? first;
        if (leftover.isNotEmpty) {
          first = leftover;
        } else if (await it.moveNext()) {
          first = it.current;
        }
        if (first == null) {
          await up.close();
          return;
        }
        final pieces = splitHandshake(first, random: _rnd);
        for (var i = 0; i < pieces.length; i++) {
          up.add(pieces[i]);
          await up.flush();
          if (pieces.length > 1 && i < pieces.length - 1) {
            await Future<void>.delayed(Duration(milliseconds: 8 + _rnd.nextInt(12)));
          }
        }
        final rest = () async* {
          while (await it.moveNext()) {
            yield it.current;
          }
        }();
        await up.addStream(rest);
        await up.close();
      }

      await Future.any([
        upstreamPump(),
        client.addStream(up).then((_) => client.close()),
      ]);
    } catch (_) {
      // Connection errors simply end this tunnel.
    } finally {
      _drop(client);
      if (upstream != null) _drop(upstream);
    }
  }

  /// Index just after the blank line that ends the HTTP headers, or -1.
  static int _headerEnd(List<int> b) {
    for (var i = 3; i < b.length; i++) {
      if (b[i - 3] == 13 && b[i - 2] == 10 && b[i - 1] == 13 && b[i] == 10) return i + 1;
    }
    return -1;
  }
}
