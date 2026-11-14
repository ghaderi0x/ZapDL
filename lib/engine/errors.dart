import 'dart:async';
import 'dart:io';

import 'models.dart';

class DownloadFailure implements Exception {
  const DownloadFailure(
    this.code, {
    this.detail,
    this.retryable = false,
    this.needsRestart = false,
  });

  final DownloadErrorCode code;
  final String? detail;
  final bool retryable;
  final bool needsRestart;

  /// Maps an HTTP status code to a failure.
  factory DownloadFailure.status(int status) {
    if (status == 401 || status == 403) {
      return DownloadFailure(DownloadErrorCode.accessDenied, detail: '$status');
    }
    if (status == 404 || status == 410) {
      return DownloadFailure(DownloadErrorCode.notFound, detail: '$status');
    }
    final retry = status == 408 || status == 429 || status >= 500;
    return DownloadFailure(DownloadErrorCode.http, detail: '$status', retryable: retry);
  }

  factory DownloadFailure.from(Object e) {
    if (e is DownloadFailure) return e;
    if (e is TimeoutException) {
      return const DownloadFailure(DownloadErrorCode.timeout, retryable: true);
    }
    if (e is TlsException) {
      return DownloadFailure(DownloadErrorCode.tls, detail: e.message);
    }
    if (e is SocketException) {
      return DownloadFailure(DownloadErrorCode.network, detail: e.message, retryable: true);
    }
    if (e is HttpException) {
      // E.g. "Connection closed while receiving data".
      return DownloadFailure(DownloadErrorCode.network, detail: e.message, retryable: true);
    }
    if (e is FileSystemException) {
      final c = e.osError?.errorCode;
      // 28 = ENOSPC (POSIX); 112/39 = disk full (Windows).
      if (c == 28 || c == 112 || c == 39) {
        return DownloadFailure(DownloadErrorCode.storageFull, detail: e.path);
      }
      // 13 = EACCES, 1 = EPERM, 30 = EROFS, 5 = Windows access denied.
      if (c == 13 || c == 1 || c == 30 || c == 5) {
        return DownloadFailure(DownloadErrorCode.permission, detail: e.path);
      }
      return DownloadFailure(DownloadErrorCode.write, detail: e.message);
    }
    if (e is FormatException || e is ArgumentError) {
      return const DownloadFailure(DownloadErrorCode.invalidUrl);
    }
    return DownloadFailure(DownloadErrorCode.unknown, detail: e.toString());
  }

  @override
  String toString() => 'DownloadFailure($code, $detail)';
}

/// Thrown internally when a runner is stopped by pause/cancel.
class StoppedException implements Exception {
  const StoppedException();
}
