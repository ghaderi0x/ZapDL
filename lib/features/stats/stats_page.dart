import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets.dart';
import '../downloads/downloads_cubit.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();

    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) {
        final completed =
            state.tasks.where((t) => t.status == DownloadStatus.completed).toList();
        final failed = state.tasks.where((t) => t.status == DownloadStatus.failed).length;
        final totalBytes = completed.fold<int>(
          0,
          (a, t) => a + (t.totalBytes > 0 ? t.totalBytes : t.receivedBytes),
        );

        // Bytes completed per day over the last 7 days (oldest first).
        final today = DateTime.now();
        final days = List.generate(
          7,
          (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)),
        );
        final perDay = <int>[
          for (final d in days)
            completed
                .where((t) {
                  final c = t.completedAt;
                  return c != null && c.year == d.year && c.month == d.month && c.day == d.day;
                })
                .fold<int>(0, (a, t) => a + (t.totalBytes > 0 ? t.totalBytes : 0)),
        ];
        final maxDay = perDay.fold<int>(0, (a, b) => a > b ? a : b);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.navStats, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  label: l.statsTotalDownloaded,
                  value: formatBytes(totalBytes, locale),
                  icon: Icons.cloud_download_outlined,
                ),
                _StatCard(
                  label: l.statsCompleted,
                  value: '${completed.length}',
                  icon: Icons.check_circle_outline_rounded,
                  color: z.success,
                ),
                _StatCard(
                  label: l.statsFailed,
                  value: '$failed',
                  icon: Icons.error_outline_rounded,
                  color: z.error,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ZapCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.statsLast7, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message: formatBytes(perDay[i], locale),
                                    child: Container(
                                      height: maxDay == 0
                                          ? 6
                                          : 6 + 110 * (perDay[i] / maxDay),
                                      decoration: BoxDecoration(
                                        // Today's bar is highlighted (ref R4).
                                        color: i == 6 ? z.accent : z.accentContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formatDayShort(days[i], locale),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: ZapCard(
        child: Row(children: [
          IconTile(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
