import 'dart:convert';
import 'dart:io';

import '../engine/errors.dart';
import '../engine/http_support.dart';
import '../engine/models.dart';
import 'media_models.dart';

/// Fetches a small text document (HTML/JSON) with the engine's proxy settings.
/// Limited to [maxBytes] so a huge page cannot exhaust memory.
Future<String> fetchText(
  Uri uri, {
  Map<String, String> headers = const {},
  ProxyConfig proxy = const ProxyConfig(),
  Duration timeout = const Duration(seconds: 20),
  int maxBytes = 3 * 1024 * 1024,
}) async {
  final client = createHttpClient(connectTimeout: timeout, proxy: proxy);
  try {
    final opened = await openGet(
      client,
      uri,
      headers: {'Accept-Language': 'en', ...headers},
      timeout: timeout,
    );
    final res = opened.response;
    if (res.statusCode == 404 || res.statusCode == 410) {
      throw const MediaException('notFound');
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const MediaException('loginRequired');
    }
    if (res.statusCode == 429) throw const MediaException('blocked');
    if (res.statusCode != 200) {
      throw MediaException('network', '${res.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in res.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) break;
    }
    return utf8.decode(bytes, allowMalformed: true);
  } on MediaException {
    rethrow;
  } on DownloadFailure catch (f) {
    throw MediaException('network', f.code.name);
  } on SocketException catch (e) {
    throw MediaException('network', e.message);
  } finally {
    client.close(force: true);
  }
}
