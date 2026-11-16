import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/platform.dart';
import '../../engine/models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'downloads_cubit.dart';

enum DownloadAction {
  pause,
  resume,
  cancel,
  retry,
  openFile,
  openFolder,
  copyUrl,
  remove,
  deleteFile,
  redownload,
}

List<DownloadAction> actionsFor(DownloadTask t) {
  final folder = isDesktopPlatform ? [DownloadAction.openFolder] : <DownloadAction>[];
  switch (t.status) {
    case DownloadStatus.downloading:
    case DownloadStatus.queued:
      return [DownloadAction.pause, DownloadAction.cancel, DownloadAction.copyUrl];
    case DownloadStatus.paused:
      return [DownloadAction.resume, DownloadAction.cancel, DownloadAction.copyUrl, DownloadAction.remove];
    case DownloadStatus.failed:
    case DownloadStatus.canceled:
      return [DownloadAction.retry, DownloadAction.copyUrl, DownloadAction.remove];
    case DownloadStatus.completed:
      if (t.fileMissing) {
        return [DownloadAction.redownload, DownloadAction.copyUrl, DownloadAction.remove];
      }
      return [
        DownloadAction.openFile,
        ...folder,
        DownloadAction.copyUrl,
        DownloadAction.remove,
        DownloadAction.deleteFile,
      ];
  }
}

String actionLabel(AppLocalizations l, DownloadAction a) => switch (a) {
      DownloadAction.pause => l.actionPause,
      DownloadAction.resume => l.actionResume,
      DownloadAction.cancel => l.actionCancel,
      DownloadAction.retry => l.actionRetry,
      DownloadAction.openFile => l.actionOpenFile,
      DownloadAction.openFolder => l.actionOpenFolder,
      DownloadAction.copyUrl => l.actionCopyUrl,
      DownloadAction.remove => l.actionRemove,
      DownloadAction.deleteFile => l.actionDeleteFile,
      DownloadAction.redownload => l.actionRedownload,
    };

IconData actionIcon(DownloadAction a) => switch (a) {
      DownloadAction.pause => Icons.pause_rounded,
      DownloadAction.resume => Icons.play_arrow_rounded,
      DownloadAction.cancel => Icons.close_rounded,
      DownloadAction.retry => Icons.refresh_rounded,
      DownloadAction.openFile => Icons.open_in_new_rounded,
      DownloadAction.openFolder => Icons.folder_open_rounded,
      DownloadAction.copyUrl => Icons.link_rounded,
      DownloadAction.remove => Icons.history_toggle_off_rounded,
      DownloadAction.deleteFile => Icons.delete_outline_rounded,
      DownloadAction.redownload => Icons.download_rounded,
    };

/// The single most useful action shown as the row's primary button.
DownloadAction? primaryActionFor(DownloadTask t) => switch (t.status) {
      DownloadStatus.downloading || DownloadStatus.queued => DownloadAction.pause,
      DownloadStatus.paused => DownloadAction.resume,
      DownloadStatus.failed || DownloadStatus.canceled => DownloadAction.retry,
      DownloadStatus.completed =>
        t.fileMissing ? DownloadAction.redownload : DownloadAction.openFile,
    };

Future<void> runDownloadAction(
  BuildContext context,
  DownloadTask t,
  DownloadAction a,
) async {
  final cubit = context.read<DownloadsCubit>();
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  switch (a) {
    case DownloadAction.pause:
      cubit.pause(t.id);
    case DownloadAction.resume:
    case DownloadAction.retry:
      await cubit.resume(t.id);
    case DownloadAction.cancel:
      await cubit.cancel(t.id);
    case DownloadAction.openFile:
      await OpenFilex.open(t.finalPath);
    case DownloadAction.openFolder:
      await revealInFileManager(t.finalPath);
    case DownloadAction.copyUrl:
      await Clipboard.setData(ClipboardData(text: t.url));
      messenger.showSnackBar(SnackBar(content: Text(l.linkCopied)));
    case DownloadAction.remove:
      await cubit.remove(t.id);
    case DownloadAction.redownload:
      try {
        await cubit.redownload(t);
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(l.statusFailed)));
      }
    case DownloadAction.deleteFile:
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.confirmDeleteTitle),
          content: Text(l.confirmDeleteBody(t.fileName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.actionClose),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.actionDelete),
            ),
          ],
        ),
      );
      if (ok == true) await cubit.remove(t.id, deleteFile: true);
  }
}
