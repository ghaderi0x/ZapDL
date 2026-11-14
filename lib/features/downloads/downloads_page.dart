import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/file_category.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/l10n_helpers.dart';
import '../../shared/widgets.dart';
import '../settings/settings_cubit.dart';
import 'add_download.dart';
import 'download_items.dart';
import 'downloads_cubit.dart';

String _statusFilterLabel(AppLocalizations l, StatusFilter f) => switch (f) {
      StatusFilter.all => l.statusAll,
      StatusFilter.active => l.statusDownloading,
      StatusFilter.completed => l.statusCompleted,
      StatusFilter.failed => l.statusFailed,
    };

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.wide});

  /// Wide layout = desktop-style table with bottom status bar (refs R2, R7).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return BlocBuilder<DownloadsCubit, DownloadsState>(
      builder: (context, state) {
        final visible = state.visible;
        return Column(
          children: [
            _Header(wide: wide, state: state),
            _StatusTabs(state: state),
            if (!wide) _CategoryChips(state: state),
            const Divider(),
            Expanded(
              child: visible.isEmpty
                  ? _EmptyState(filtered: state.tasks.isNotEmpty)
                  : wide
                      ? Column(children: [
                          const DownloadTableHeader(),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: visible.length,
                              itemBuilder: (_, i) =>
                                  DownloadRow(key: ValueKey(visible[i].id), task: visible[i]),
                            ),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) =>
                              DownloadCard(key: ValueKey(visible[i].id), task: visible[i]),
                        ),
            ),
            if (wide) _StatusBar(state: state, l: l),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.wide, required this.state});

  final bool wide;
  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final cubit = context.read<DownloadsCubit>();
    final locale = Localizations.localeOf(context).toString();

    final search = TextField(
      onChanged: cubit.setQuery,
      decoration: InputDecoration(
        hintText: l.searchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
      ),
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          // Prominent "add or paste" field, like ref R7's top bar.
          Expanded(
            flex: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(ZapRadii.input),
              onTap: () => showAddDownload(context),
              child: IgnorePointer(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l.addOrPasteUrl,
                    prefixIcon: Icon(Icons.add_rounded, color: z.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: search),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l.actionPauseAll,
            icon: const Icon(Icons.pause_circle_outline_rounded),
            onPressed: cubit.pauseAll,
          ),
          IconButton(
            tooltip: l.actionResumeAll,
            icon: const Icon(Icons.play_circle_outline_rounded),
            onPressed: cubit.resumeAll,
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.navDownloads, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          ZapCard(
            radius: ZapRadii.cardMobile,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              Icon(Icons.bolt_rounded, color: z.accent),
              const SizedBox(width: 8),
              Text(formatSpeed(state.totalSpeed, locale),
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(l.activeCount(state.activeCount),
                  style: Theme.of(context).textTheme.bodySmall),
              IconButton(
                tooltip: l.actionPauseAll,
                icon: const Icon(Icons.pause_rounded),
                onPressed: cubit.pauseAll,
              ),
              IconButton(
                tooltip: l.actionResumeAll,
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: cubit.resumeAll,
              ),
            ]),
          ),
          const SizedBox(height: 12),
          search,
        ],
      ),
    );
  }
}

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.state});

  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final cubit = context.read<DownloadsCubit>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in StatusFilter.values)
            InkWell(
              onTap: () => cubit.setFilter(f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: state.filter == f ? z.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: _statusFilterLabel(l, f),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: state.filter == f ? z.accent : z.text,
                    ),
                  ),
                  TextSpan(
                    text: '  ${state.countFor(f)}',
                    style: TextStyle(color: z.textMuted, fontSize: 12),
                  ),
                ])),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.state});

  final DownloadsState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final cubit = context.read<DownloadsCubit>();
    final items = <FileCategory?>[null, ...FileCategory.values];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = items[i];
          final selected = state.category == c;
          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            label: Text(categoryLabel(l, c)),
            avatar: c == null ? null : Icon(categoryIcon(c), size: 16),
            selectedColor: z.accentContainer,
            labelStyle: TextStyle(color: selected ? z.accent : z.text),
            onSelected: (_) => cubit.setCategory(c),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(icon: Icons.download_rounded, size: 64),
            const SizedBox(height: 16),
            Text(filtered ? l.emptyFiltered : l.emptyTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (!filtered)
              Text(l.emptyBody,
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            if (!filtered) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => showAddDownload(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.addTitle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.l});

  final DownloadsState state;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();
    final limit = context.watch<SettingsCubit>().state.speedLimitKb;
    final style = Theme.of(context).textTheme.labelSmall;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: z.outline))),
      child: Row(children: [
        Text(l.activeCount(state.activeCount), style: style),
        const Spacer(),
        Icon(Icons.speed_rounded, size: 14, color: z.textMuted),
        const SizedBox(width: 4),
        Text(limit == 0 ? l.speedLimitNone : formatSpeed(limit * 1024, locale), style: style),
        const SizedBox(width: 16),
        Icon(Icons.arrow_downward_rounded, size: 14, color: z.accent),
        const SizedBox(width: 4),
        Text(formatSpeed(state.totalSpeed, locale), style: style),
      ]),
    );
  }
}
