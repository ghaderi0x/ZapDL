import 'dart:io';

/// Reads the operating system's HTTP proxy, because dart:io only looks at the
/// HTTP_PROXY / HTTPS_PROXY environment variables and so ignores the proxy that
/// VPN and v2ray-style tools set in Windows ("System proxy").
///
/// Supported: Windows (Internet Settings registry), macOS (`scutil --proxy`),
/// then the environment variables everywhere. SOCKS-only proxies cannot be used
/// by dart:io, so they are ignored (the connection goes direct).
class SystemProxy {
  SystemProxy._();

  static DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
  static ({String host, int port})? _cached;

  /// Value for `HttpClient.findProxy`.
  static String forUri(Uri uri) {
    final p = _lookup();
    if (p != null && !_bypassed(uri)) return 'PROXY ${p.host}:${p.port}';
    return HttpClient.findProxyFromEnvironment(uri);
  }

  static bool _bypassed(Uri uri) {
    final h = uri.host;
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  static ({String host, int port})? _lookup() {
    final now = DateTime.now();
    if (now.difference(_at) < const Duration(seconds: 60)) return _cached;
    _at = now;
    try {
      if (Platform.isWindows) {
        _cached = _windows();
      } else if (Platform.isMacOS) {
        _cached = _mac();
      } else {
        _cached = null;
      }
    } catch (_) {
      _cached = null;
    }
    return _cached;
  }

  static String? _regValue(String name) {
    final r = Process.runSync('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      name,
    ]);
    if (r.exitCode != 0) return null;
    final m = RegExp('$name\\s+REG_\\w+\\s+(.+)').firstMatch(r.stdout as String);
    return m?.group(1)?.trim();
  }

  static ({String host, int port})? _windows() {
    final enabled = _regValue('ProxyEnable');
    if (enabled == null || int.tryParse(enabled.replaceFirst('0x', ''), radix: 16) != 1) {
      return null;
    }
    final server = _regValue('ProxyServer');
    if (server == null || server.isEmpty) return null;
    return parseProxyServer(server);
  }

  /// Parses "host:port" or "http=host:port;https=host:port;socks=host:port".
  static ({String host, int port})? parseProxyServer(String server) {
    String? pick;
    if (server.contains('=')) {
      final parts = <String, String>{};
      for (final seg in server.split(';')) {
        final i = seg.indexOf('=');
        if (i > 0) parts[seg.substring(0, i).trim().toLowerCase()] = seg.substring(i + 1).trim();
      }
      pick = parts['https'] ?? parts['http'];
    } else {
      pick = server.trim();
    }
    if (pick == null) return null;
    pick = pick.replaceFirst(RegExp(r'^\w+://'), '');
    final i = pick.lastIndexOf(':');
    if (i <= 0) return null;
    final port = int.tryParse(pick.substring(i + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return (host: pick.substring(0, i), port: port);
  }

  static ({String host, int port})? _mac() {
    final r = Process.runSync('scutil', ['--proxy']);
    if (r.exitCode != 0) return null;
    final out = r.stdout as String;
    String? v(String k) => RegExp('$k\\s*:\\s*(\\S+)').firstMatch(out)?.group(1);
    if (v('HTTPSEnable') == '1') {
      final port = int.tryParse(v('HTTPSPort') ?? '');
      final host = v('HTTPSProxy');
      if (host != null && port != null) return (host: host, port: port);
    }
    if (v('HTTPEnable') == '1') {
      final port = int.tryParse(v('HTTPPort') ?? '');
      final host = v('HTTPProxy');
      if (host != null && port != null) return (host: host, port: port);
    }
    return null;
  }
}
