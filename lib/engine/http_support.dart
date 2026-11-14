import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'models.dart';
import 'system_proxy.dart';

const defaultUserAgent = 'ZapDL/0.1';

/// Where credentials (Cookie, Authorization, ...) live. They are never written
/// to the downloads JSON. The app provides a secure-storage implementation.
abstract class SecretStore {
  Future<Map<String, String>> read(String downloadId);
  Future<void> write(String downloadId, Map<String, String> secrets);
  Future<void> delete(String downloadId);
}

/// Keeps secrets in memory only: they are lost when the app exits.
class InMemorySecretStore implements SecretStore {
  final Map<String, Map<String, String>> _data = {};

  @override
  Future<Map<String, String>> read(String id) async => Map.of(_data[id] ?? const {});

  @override
  Future<void> write(String id, Map<String, String> secrets) async {
    if (secrets.isEmpty) {
      _data.remove(id);
    } else {
      _data[id] = Map.of(secrets);
    }
  }

  @override
  Future<void> delete(String id) async => _data.remove(id);
}

/// Headers the engine controls itself; callers cannot override them.
const _reserved = {
  'host',
  'range',
  'accept-encoding',
  'content-length',
  'transfer-encoding',
  'connection',
  'upgrade',
  'te',
  'if-range',
};

/// Headers that carry credentials and so go to the [SecretStore].
const _secretNames = {
  'cookie',
  'authorization',
  'proxy-authorization',
  'x-api-key',
  'x-auth-token',
};

final _tokenRe = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

/// Throws [DownloadErrorCode.invalidHeader] for malformed or reserved headers.
/// Rejects CR/LF/NUL in values so a header can never smuggle another one.
void validateHeaders(Map<String, String> headers) {
  for (final e in headers.entries) {
    final name = e.key.trim();
    if (!_tokenRe.hasMatch(name) || _reserved.contains(name.toLowerCase())) {
      throw DownloadFailure(DownloadErrorCode.invalidHeader, detail: name);
    }
    if (e.value.contains(RegExp(r'[\r\n\x00]'))) {
      throw DownloadFailure(DownloadErrorCode.invalidHeader, detail: name);
    }
  }
}

bool isSecretHeader(String name) => _secretNames.contains(name.trim().toLowerCase());

/// Splits [all] into storable headers and credentials. Validates first.
({Map<String, String> plain, Map<String, String> secret}) splitHeaders(
  Map<String, String> all,
) {
  validateHeaders(all);
  final plain = <String, String>{};
  final secret = <String, String>{};
  for (final e in all.entries) {
    final name = e.key.trim();
    if (e.value.trim().isEmpty) continue;
    (isSecretHeader(name) ? secret : plain)[name] = e.value.trim();
  }
  return (plain: plain, secret: secret);
}

/// Removes `user:password@` from a URL and returns it as a Basic
/// Authorization header instead, so the password is never stored in the URL.
({String url, String? authorization}) extractUserInfo(String url) {
  final trimmed = url.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.userInfo.isEmpty) return (url: trimmed, authorization: null);
  final stripped = trimmed.replaceFirst(RegExp(r'//[^/?#@]*@'), '//');
  String info;
  try {
    info = Uri.decodeComponent(uri.userInfo);
  } catch (_) {
    info = uri.userInfo;
  }
  return (
    url: stripped,
    authorization: 'Basic ${base64.encode(utf8.encode(info))}',
  );
}

/// Creates an [HttpClient] using [proxy]. Manual proxies are HTTP proxies
/// (HTTPS targets use CONNECT); SOCKS is not supported by dart:io.
HttpClient createHttpClient({
  required Duration connectTimeout,
  ProxyConfig proxy = const ProxyConfig(),
}) {
  final client = HttpClient()
    ..connectionTimeout = connectTimeout
    ..userAgent = defaultUserAgent;
  switch (proxy.mode) {
    case ProxyMode.system:
      // OS proxy (Windows/macOS settings) first, then HTTP_PROXY / HTTPS_PROXY.
      client.findProxy = SystemProxy.forUri;
    case ProxyMode.none:
      client.findProxy = (_) => 'DIRECT';
    case ProxyMode.manual:
      if (!proxy.isManualValid) {
        throw const DownloadFailure(DownloadErrorCode.proxy);
      }
      final u = proxy.username ?? '';
      final pw = proxy.password ?? '';
      final auth = (u.isNotEmpty && pw.isNotEmpty) ? '$u:$pw@' : '';
      final target = 'PROXY $auth${proxy.host}:${proxy.port}';
      client.findProxy = (_) => target;
  }
  return client;
}

class OpenedResponse {
  OpenedResponse(this.response, this.uri);
  final HttpClientResponse response;

  /// The URL that produced [response], after redirects.
  final Uri uri;
}

bool _isRedirect(int s) => s == 301 || s == 302 || s == 303 || s == 307 || s == 308;

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme && a.host == b.host && a.port == b.port;

/// GET with manual redirect handling so credentials are only ever sent to the
/// origin they were meant for (never after a redirect to another host/scheme).
Future<OpenedResponse> openGet(
  HttpClient client,
  Uri uri, {
  Map<String, String> headers = const {},
  Map<String, String> secrets = const {},
  String? range,
  Duration? timeout,
  int maxRedirects = 8,
}) async {
  var current = uri;
  var sendSecrets = true;
  for (var hop = 0; hop <= maxRedirects; hop++) {
    final req = client.getUrl(current);
    final request = await (timeout == null ? req : req.timeout(timeout));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);
    if (sendSecrets) secrets.forEach(request.headers.set);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final closing = request.close();
    final response = await (timeout == null ? closing : closing.timeout(timeout));
    if (!_isRedirect(response.statusCode)) return OpenedResponse(response, current);

    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (location == null) throw DownloadFailure.status(response.statusCode);
    final next = current.resolve(location);
    if (next.scheme != 'http' && next.scheme != 'https') {
      throw const DownloadFailure(DownloadErrorCode.invalidUrl);
    }
    if (!_sameOrigin(current, next)) sendSecrets = false;
    current = next;
  }
  throw const DownloadFailure(DownloadErrorCode.http, detail: 'too many redirects');
}
