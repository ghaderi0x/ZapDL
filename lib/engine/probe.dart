import 'dart:io';

import 'package:path/path.dart' as p;

import 'errors.dart';
import 'file_utils.dart';
import 'http_support.dart';
import 'models.dart';

const userAgent = defaultUserAgent;

class ProbeResult {
  const ProbeResult({
    required this.finalUrl,
    required this.fileName,
    required this.totalBytes,
    required this.rangeSupported,
    this.etag,
    this.lastModified,
    this.mimeType,
  });

  final String finalUrl;
  final String fileName;

  /// -1 when the server does not report a length.
  final int totalBytes;

  /// True only when the server actually answered a Range request with 206.
  final bool rangeSupported;
  final String? etag;
  final String? lastModified;
  final String? mimeType;
}

/// Validates a user-typed URL. Only http/https are implemented; ftp/sftp are
/// recognized so the UI can report them as unsupported rather than "invalid".
Uri parseDownloadUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw const DownloadFailure(DownloadErrorCode.invalidUrl);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'ftp' || scheme == 'sftp' || scheme == 'ftps') {
    throw DownloadFailure(DownloadErrorCode.unsupportedScheme, detail: scheme);
  }
  if (scheme != 'http' && scheme != 'https') {
    throw const DownloadFailure(DownloadErrorCode.invalidUrl);
  }
  return uri;
}

bool looksLikeDownloadUrl(String text) {
  final t = text.trim();
  if (t.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(t);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String? parseContentDisposition(String? header) {
  if (header == null) return null;
  final star = RegExp(r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)", caseSensitive: false)
      .firstMatch(header);
  if (star != null) {
    try {
      return Uri.decodeComponent(star.group(2)!.trim());
    } catch (_) {}
  }
  final plain =
      RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(header);
  return plain?.group(1)?.trim();
}

/// Sends a `Range: bytes=0-0` GET to learn size, range support, validators and
/// file name without downloading the body.
Future<ProbeResult> probeUrl(
  String url, {
  Duration timeout = const Duration(seconds: 30),
  Duration connectTimeout = const Duration(seconds: 20),
  Map<String, String> headers = const {},
  Map<String, String> secretHeaders = const {},
  ProxyConfig proxy = const ProxyConfig(),
}) async {
  final uri = parseDownloadUri(url);
  HttpClient? client;
  try {
    client = createHttpClient(connectTimeout: connectTimeout, proxy: proxy);
    final opened = await openGet(
      client,
      uri,
      headers: headers,
      secrets: secretHeaders,
      range: 'bytes=0-0',
      timeout: timeout,
    );
    final response = opened.response;
    final status = response.statusCode;

    if (status != 200 && status != 206) {
      throw DownloadFailure.status(status);
    }

    var total = -1;
    var ranges = false;
    if (status == 206) {
      ranges = true;
      final cr = response.headers.value(HttpHeaders.contentRangeHeader);
      final m = cr == null ? null : RegExp(r'/(\d+)\s*$').firstMatch(cr);
      if (m != null) total = int.parse(m.group(1)!);
    } else {
      total = response.contentLength;
    }

    final finalUri = opened.uri;

    final dispositionName =
        parseContentDisposition(response.headers.value('content-disposition'));
    String urlName = '';
    if (finalUri.pathSegments.isNotEmpty) {
      try {
        urlName = Uri.decodeComponent(finalUri.pathSegments.last);
      } catch (_) {
        urlName = finalUri.pathSegments.last;
      }
    }
    final rawName = (dispositionName != null && dispositionName.isNotEmpty)
        ? dispositionName
        : (urlName.isNotEmpty ? urlName : finalUri.host);

    final mime = response.headers.contentType?.mimeType;

    return ProbeResult(
      finalUrl: finalUri.toString(),
      fileName: sanitizeFileName(rawName),
      totalBytes: total,
      rangeSupported: ranges && total > 0,
      etag: response.headers.value(HttpHeaders.etagHeader),
      lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
      mimeType: mime,
    );
  } catch (e) {
    throw DownloadFailure.from(e);
  } finally {
    // Force-close so an un-drained body (server ignored Range) is not downloaded.
    client?.close(force: true);
  }
}

/// Splits [total] bytes into contiguous ranges. Falls back to one segment when
/// ranges are unsupported or the length is unknown (never corrupts a file by
/// combining ranges the server cannot serve).
List<Segment> planSegments({
  required int total,
  required bool ranges,
  required int connections,
  required int minSegmentBytes,
}) {
  if (!ranges || total <= 0) {
    return [Segment(start: 0, end: total > 0 ? total - 1 : -1)];
  }
  var n = total ~/ minSegmentBytes;
  if (n > connections) n = connections;
  if (n < 1) n = 1;
  final base = total ~/ n;
  return [
    for (var i = 0; i < n; i++)
      Segment(
        start: i * base,
        end: i == n - 1 ? total - 1 : (i + 1) * base - 1,
      ),
  ];
}

String partFileName(String partsDir, int index) => p.join(partsDir, 'part$index');
