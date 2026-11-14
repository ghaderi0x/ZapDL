import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/l10n_helpers.dart';
import '../../shared/widgets.dart';
import 'download_actions.dart';
import 'downloads_cubit.dart';

/// Shows everything known about one download. Uses a dialog on wide screens
/// and a bottom sheet on phones, and stays live while the download progresses.
Future<void> showDownloadDetails(BuildContext context, DownloadTask task) {
  final cubit = context.read<DownloadsCubit>();
  final wide = MediaQuery.sizeOf(context).width >= 640;
  Widget body() => BlocProvider.value(
        value: cubit,
        child: DownloadDetailsView(taskId: task.id, fallback: task),
      );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: body()),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => body(),
  );
}

class DownloadDetailsView extends StatelessWidget {
  const DownloadDetailsView({super.key, required this.taskId, required this.fallback});

  final String taskId;
  final DownloadTask fallback;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();

    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) {
        final t = state.tasks.firstWhere((x) => x.id == taskId, orElse: () => fallback);
        Widget row(String label, String value, {bool selectable = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  selectable
                      ? SelectableText(value, style: Theme.of(context).textTheme.bodyMedium)
                      : Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.detailsTitle, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              GradientProgressBar(value: t.status == DownloadStatus.completed ? 1 : t.progress),
              const SizedBox(height: 8),
              row(l.colName, t.fileName, selectable: true),
              row(l.colStatus, t.fileMissing ? l.statusFileDeleted : statusLabel(l, t.status)),
              if (t.status == DownloadStatus.failed)
                row(l.statusFailed, errorText(l, t.errorCode, t.errorDetail)),
              row(
                l.colSize,
                t.totalBytes > 0
                    ? '${formatBytes(t.receivedBytes, locale)} / ${formatBytes(t.totalBytes, locale)}'
                    : formatBytes(t.receivedBytes, locale),
              ),
              row(l.detailsSource, t.url, selectable: true),
              row(l.detailsDestination, t.directory, selectable: true),
              row(l.detailsConnections, formatInt(t.segments.isEmpty ? 1 : t.segments.length, locale)),
              row(l.detailsResumable, t.rangeSupported ? l.detailsYes : l.detailsNo),
              row(l.detailsAdded, formatDateTime(t.createdAt, locale)),
              if (t.completedAt != null)
                row(l.statusCompleted, formatDateTime(t.completedAt!, locale)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => runDownloadAction(context, t, DownloadAction.copyUrl),
                    icon: Icon(Icons.link_rounded, color: z.textMuted),
                    label: Text(l.actionCopyUrl),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.actionClose),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
