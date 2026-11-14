import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/l10n_helpers.dart';
import '../../shared/widgets.dart';
import 'download_actions.dart';
import 'download_details.dart';
import 'downloads_cubit.dart';

Color _statusColor(ZapColors z, DownloadTask t) => switch (t.status) {
      DownloadStatus.completed => t.fileMissing ? z.warning : z.success,
      DownloadStatus.failed => z.error,
      DownloadStatus.paused || DownloadStatus.canceled => z.textMuted,
      _ => z.accent,
    };

String _statusText(AppLocalizations l, DownloadTask t, String locale) {
  if (t.fileMissing) return l.statusFileDeleted;
  if (t.status == DownloadStatus.queued && t.scheduledAt != null) {
    return l.statusScheduled(formatDateTime(t.scheduledAt!, locale));
  }
  return statusLabel(l, t.status);
}

String _subtitle(AppLocalizations l, DownloadTask t, String locale) {
  if (t.fileMissing) return '${l.statusFileDeleted} · ${l.fileDeletedHint}';
  if (t.status == DownloadStatus.failed) {
    return errorText(l, t.errorCode, t.errorDetail);
  }
  if (t.status == DownloadStatus.queued && t.scheduledAt != null) {
    return l.statusScheduled(formatDateTime(t.scheduledAt!, locale));
  }
  return statusLabel(l, t.status);
}

/// Opens the same action menu on right-click (desktop context menu, ref R6).
Future<void> _showContextMenu(
  BuildContext context,
  DownloadTask t,
  Offset position,
) async {
  final l = AppLocalizations.of(context);
  final z = context.zap;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<DownloadAction>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final a in actionsFor(t))
        PopupMenuItem(
          value: a,
          child: Row(children: [
            Icon(actionIcon(a), size: 18, color: z.textMuted),
            const SizedBox(width: 12),
            Text(actionLabel(l, a)),
          ]),
        ),
    ],
  );
  if (selected != null && context.mounted) {
    await runDownloadAction(context, t, selected);
  }
}

class DownloadMenuButton extends StatelessWidget {
  const DownloadMenuButton({super.key, required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    return PopupMenuButton<DownloadAction>(
      icon: Icon(Icons.more_vert_rounded, color: z.textMuted),
      onSelected: (a) => runDownloadAction(context, task, a),
      itemBuilder: (_) => [
        for (final a in actionsFor(task))
          PopupMenuItem(
            value: a,
            child: Row(children: [
              Icon(actionIcon(a), size: 18, color: z.textMuted),
              const SizedBox(width: 12),
              Flexible(child: Text(actionLabel(l, a))),
            ]),
          ),
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final a = primaryActionFor(task);
    if (a == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return IconButton(
      tooltip: actionLabel(l, a),
      icon: Icon(actionIcon(a)),
      color: context.zap.accent,
      onPressed: () => runDownloadAction(context, task, a),
    );
  }
}

/// Compact card used on mobile/medium widths (refs R3 + R4 queue rows).
class DownloadCard extends StatelessWidget {
  const DownloadCard({super.key, required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();
    final t = task;
    final category = DownloadsState.categoryOf(t);
    final showBar = t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.paused ||
        t.status == DownloadStatus.queued ||
        (t.status == DownloadStatus.failed && t.receivedBytes > 0);
    final failed = t.status == DownloadStatus.failed ||
        t.status == DownloadStatus.canceled ||
        t.fileMissing;

    return ZapCard(
        onTap: () => showDownloadDetails(context, t),
        onSecondaryTapDown: (d) => _showContextMenu(context, t, d.globalPosition),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon: categoryIcon(category)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              decoration: failed ? TextDecoration.lineThrough : null,
                              color: failed ? z.textMuted : null,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(l, t, locale),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: _statusColor(z, t)),
                      ),
                    ],
                  ),
                ),
                if (t.status == DownloadStatus.downloading && t.progress != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Text(
                      formatPercent(t.progress!, locale),
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: z.accent),
                    ),
                  ),
                _PrimaryActionButton(task: t),
                DownloadMenuButton(task: t),
              ],
            ),
            if (showBar) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 10),
                child: GradientProgressBar(
                  value: t.progress,
                  solidColor: t.status == DownloadStatus.paused
                      ? z.textMuted
                      : (t.status == DownloadStatus.failed ? z.error : null),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                InfoChip(
                  icon: Icons.download_rounded,
                  label: t.status == DownloadStatus.completed
                      ? formatBytes(t.totalBytes > 0 ? t.totalBytes : t.receivedBytes, locale)
                      : t.totalBytes > 0
                          ? '${formatBytes(t.receivedBytes, locale)} / ${formatBytes(t.totalBytes, locale)}'
                          : formatBytes(t.receivedBytes, locale),
                ),
                if (t.etaSeconds != null)
                  InfoChip(
                    icon: Icons.schedule_rounded,
                    label: formatDuration(t.etaSeconds!, locale),
                  ),
                if (t.status == DownloadStatus.downloading)
                  InfoChip(
                    icon: Icons.speed_rounded,
                    label: formatSpeed(t.speedBps, locale),
                    filled: true,
                  ),
                if (t.status == DownloadStatus.completed && t.completedAt != null)
                  InfoChip(
                    icon: Icons.event_available_rounded,
                    label: formatDate(t.completedAt!, locale),
                  ),
              ],
            ),
          ],
        ),
    );
  }
}

/// Table header for the wide layout (ref R2).
class DownloadTableHeader extends StatelessWidget {
  const DownloadTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.labelSmall;
    Widget cell(String text, int flex, {double? width}) {
      final w = Text(text, style: style);
      return width != null ? SizedBox(width: width, child: w) : Expanded(flex: flex, child: w);
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 100, 8),
      child: Row(
        children: [
          cell(l.colName, 4),
          cell(l.colSize, 0, width: 100),
          cell(l.colStatus, 0, width: 190),
          cell(l.timeLeft, 0, width: 90),
          cell(l.colDate, 0, width: 100),
        ],
      ),
    );
  }
}

/// Dense table row for wide layouts (ref R2).
class DownloadRow extends StatefulWidget {
  const DownloadRow({super.key, required this.task});

  final DownloadTask task;

  @override
  State<DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends State<DownloadRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();
    final t = widget.task;
    final category = DownloadsState.categoryOf(t);
    final textTheme = Theme.of(context).textTheme;
    final active = t.status == DownloadStatus.downloading ||
        t.status == DownloadStatus.paused ||
        t.status == DownloadStatus.queued;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showDownloadDetails(context, t),
        onSecondaryTapDown: (d) => _showContextMenu(context, t, d.globalPosition),
        onDoubleTap: t.status == DownloadStatus.completed
            ? () => runDownloadAction(context, t, DownloadAction.openFile)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 60,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
          decoration: BoxDecoration(
            color: _hover ? z.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(ZapRadii.input),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(children: [
                  Icon(categoryIcon(category), color: z.textMuted, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyLarge),
                        Text(categoryLabel(l, category), style: textTheme.labelSmall),
                      ],
                    ),
                  ),
                ]),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  t.totalBytes > 0 ? formatBytes(t.totalBytes, locale) : '—',
                  style: textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                width: 190,
                child: active && t.status != DownloadStatus.queued
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              if (t.progress != null) formatPercent(t.progress!, locale),
                              if (t.status == DownloadStatus.downloading)
                                formatSpeed(t.speedBps, locale)
                              else
                                _statusText(l, t, locale),
                            ].join('  ·  '),
                            style: textTheme.labelSmall,
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 24),
                            child: GradientProgressBar(
                              value: t.progress,
                              solidColor:
                                  t.status == DownloadStatus.paused ? z.textMuted : null,
                            ),
                          ),
                        ],
                      )
                    : Tooltip(
                        message: t.status == DownloadStatus.failed
                            ? errorText(l, t.errorCode, t.errorDetail)
                            : '',
                        child: Text(
                          _statusText(l, t, locale),
                          style: textTheme.bodyMedium?.copyWith(color: _statusColor(z, t)),
                        ),
                      ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  t.etaSeconds != null ? formatDuration(t.etaSeconds!, locale) : '—',
                  style: textTheme.bodyMedium,
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  formatDate(t.completedAt ?? t.createdAt, locale),
                  style: textTheme.bodyMedium,
                ),
              ),
              _PrimaryActionButton(task: t),
              DownloadMenuButton(task: t),
            ],
          ),
        ),
      ),
    );
  }
}
