import '../engine/file_category.dart';
import '../engine/models.dart';
import '../l10n/gen/app_localizations.dart';
import '../media/media_models.dart';

String statusLabel(AppLocalizations l, DownloadStatus s) => switch (s) {
      DownloadStatus.queued => l.statusQueued,
      DownloadStatus.downloading => l.statusDownloading,
      DownloadStatus.paused => l.statusPaused,
      DownloadStatus.completed => l.statusCompleted,
      DownloadStatus.failed => l.statusFailed,
      DownloadStatus.canceled => l.statusCanceled,
    };

String categoryLabel(AppLocalizations l, FileCategory? c) => switch (c) {
      null => l.catAll,
      FileCategory.video => l.catVideos,
      FileCategory.audio => l.catAudio,
      FileCategory.image => l.catImages,
      FileCategory.document => l.catDocuments,
      FileCategory.archive => l.catArchives,
      FileCategory.application => l.catApplications,
      FileCategory.other => l.catOther,
    };

String errorText(AppLocalizations l, DownloadErrorCode? code, String? detail) =>
    switch (code) {
      null => l.errUnknown,
      DownloadErrorCode.network => l.errNetwork,
      DownloadErrorCode.timeout => l.errTimeout,
      DownloadErrorCode.http => l.errHttp(detail ?? '?'),
      DownloadErrorCode.notFound => l.errNotFound,
      DownloadErrorCode.accessDenied => l.errAccessDenied,
      DownloadErrorCode.rangeIgnored => l.errRangeIgnored,
      DownloadErrorCode.changed => l.errChanged,
      DownloadErrorCode.storageFull => l.errStorageFull,
      DownloadErrorCode.permission => l.errPermission,
      DownloadErrorCode.write => l.errWrite,
      DownloadErrorCode.incomplete => l.errIncomplete,
      DownloadErrorCode.invalidUrl => l.errInvalidUrl,
      DownloadErrorCode.unsupportedScheme => l.errUnsupported,
      DownloadErrorCode.tls => l.errTls,
      DownloadErrorCode.invalidHeader => l.errInvalidHeader,
      DownloadErrorCode.proxy => l.errProxy,
      DownloadErrorCode.unknown => l.errUnknown,
    };

String mediaErrorText(AppLocalizations l, MediaException e) => switch (e.reason) {
      'notFound' => l.mediaErrNotFound,
      'loginRequired' => l.mediaErrLogin,
      'blocked' => l.mediaErrBlocked,
      'network' => l.mediaErrNetwork,
      'parse' => l.mediaErrParse,
      _ => l.mediaErrUnsupported,
    };

String? mediaNoteText(AppLocalizations l, String? note) =>
    note == 'videoOnlyNoSound' ? l.mediaNoteVideoOnly : null;
