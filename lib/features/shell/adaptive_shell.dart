import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di.dart';
import '../../core/format.dart';
import '../../core/platform.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/engine.dart';
import '../../engine/file_category.dart';
import '../../engine/models.dart';
import '../../engine/probe.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../platform/incoming_links.dart';
import '../../platform/url_import.dart';
import '../../update/update_cubit.dart';
import '../../shared/l10n_helpers.dart';
import '../../shared/widgets.dart';
import '../downloads/add_download.dart';
import '../downloads/downloads_cubit.dart';
import '../downloads/downloads_page.dart';
import '../settings/settings_cubit.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';

/// Chooses navigation by width, not by platform: bottom pill nav on phones
/// (ref R1), icon rail on medium widths (ref R5), full sidebar on wide
/// windows (refs R2, R7).
class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key});

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> with WidgetsBindingObserver {
  int _tab = 0;
  String? _lastOfferedUrl;
  bool _dragging = false;
  StreamSubscription<List<String>>? _linksSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerClipboardUrl());
    if (getIt.isRegistered<IncomingLinks>()) {
      _linksSub = getIt<IncomingLinks>().stream.listen(_handleLinks);
    }
  }

  @override
  void dispose() {
    _linksSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Links from the share sheet or dropped files. One link opens the normal
  /// add dialog (so quality/cookies can be chosen); several are added together.
  Future<void> _handleLinks(List<String> urls) async {
    if (!mounted || urls.isEmpty) return;
    final l = AppLocalizations.of(context);
    if (urls.length == 1) {
      await showAddDownload(context, initialUrl: urls.first);
      return;
    }
    final downloads = context.read<DownloadsCubit>();
    final dir = context.read<SettingsCubit>().state.downloadDir;
    final messenger = ScaffoldMessenger.of(context);
    final r = await downloads.addMany(urls, dir);
    messenger.showSnackBar(SnackBar(
      content: Text(r.failed == 0
          ? l.bulkAdded(r.added)
          : '${l.bulkAdded(r.added)} · ${l.bulkFailed(r.failed)}'),
    ));
  }

  Future<void> _onDrop(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final urls = <String>[];
    for (final f in d.files) {
      urls.addAll(await urlsFromFile(f.path));
    }
    await _handleLinks(urls.toSet().toList());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<DownloadsCubit>().refreshFiles();
      _offerClipboardUrl();
    }
  }

  /// Offers (never forces) adding a URL found on the clipboard. Skipped on iOS,
  /// where reading the clipboard shows a system paste prompt; iOS users use the
  /// Paste button in the add dialog instead.
  Future<void> _offerClipboardUrl() async {
    if (Platform.isIOS || !mounted) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (!mounted || text == null || !looksLikeDownloadUrl(text)) return;
      if (text == _lastOfferedUrl) return;
      if (context.read<DownloadsCubit>().isDuplicate(text)) return;
      _lastOfferedUrl = text;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.clipboardLinkFound),
          action: SnackBarAction(
            label: l.actionAdd,
            onPressed: () => showAddDownload(context, initialUrl: text),
          ),
        ),
      );
    } catch (_) {
      // Clipboard unavailable: ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 640;
    final expanded = width >= 900;

    final pages = Column(
      children: [
        _Banners(tab: _tab, onOpenSettings: () => setState(() => _tab = 2)),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              DownloadsPage(wide: wide),
              const StatsPage(),
              const SettingsPage(),
            ],
          ),
        ),
      ],
    );

    Widget shell = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            showAddDownload(context),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            showAddDownload(context),
      },
      child: Focus(
        autofocus: true,
        child: wide
            ? Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      _Sidebar(
                        compact: !expanded,
                        tab: _tab,
                        onTab: (i) => setState(() => _tab = i),
                      ),
                      VerticalDivider(width: 1, color: context.zap.outline),
                      Expanded(child: pages),
                    ],
                  ),
                ),
              )
            : Scaffold(
                body: Stack(
                  children: [
                    // Soft accent glow at the top of the screen (ref R1).
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(0, -1.1),
                            radius: 1.0,
                            colors: [context.zap.glow, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(child: pages),
                  ],
                ),
                floatingActionButton: _tab == 0
                    ? FloatingActionButton(
                        onPressed: () => showAddDownload(context),
                        child: const Icon(Icons.add_rounded),
                      )
                    : null,
                bottomNavigationBar: _PillNav(
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
              ),
      ),
    );

    if (isDesktopPlatform) {
      final l = AppLocalizations.of(context);
      shell = DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: _onDrop,
        child: Stack(children: [
          Positioned.fill(child: shell),
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: context.zap.accent.withValues(alpha: 0.15),
                  alignment: Alignment.center,
                  child: Text(l.dropHere, style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ),
        ]),
      );
    }
    return shell;
  }
}

/// Status banners above the pages: why nothing is transferring, and a new
/// version being available.
class _Banners extends StatelessWidget {
  const _Banners({required this.tab, required this.onOpenSettings});

  final int tab;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    Widget banner(IconData icon, Color color, String text, {VoidCallback? onTap, String? action}) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: ZapCard(
            color: color.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
              if (onTap != null && action != null)
                TextButton(onPressed: onTap, child: Text(action)),
            ]),
          ),
        );

    return Column(children: [
      BlocBuilder<DownloadsCubit, DownloadsState>(
        buildWhen: (a, b) => a.gate != b.gate || a.tasks.length != b.tasks.length,
        builder: (context, s) {
          final waiting = s.tasks.any((t) =>
              t.status == DownloadStatus.queued || t.status == DownloadStatus.downloading);
          if (s.gate == EngineGate.open || !waiting) return const SizedBox.shrink();
          final text = switch (s.gate) {
            EngineGate.network => l.gateNetwork,
            EngineGate.schedule => l.gateSchedule,
            EngineGate.suspended => l.gateSuspended,
            EngineGate.open => '',
          };
          return banner(Icons.hourglass_top_rounded, z.warning, text);
        },
      ),
      BlocBuilder<UpdateCubit, UpdateState>(
        buildWhen: (a, b) => a.phase != b.phase || a.release?.tag != b.release?.tag,
        builder: (context, u) {
          final show = tab != 2 &&
              u.release != null &&
              (u.phase == UpdatePhase.available ||
                  u.phase == UpdatePhase.downloading ||
                  (u.phase == UpdatePhase.ready && u.localNote == null));
          if (!show) return const SizedBox.shrink();
          return banner(
            Icons.system_update_alt_rounded,
            z.accent,
            l.updateAvailable(u.release!.version.toString()),
            onTap: onOpenSettings,
            action: l.updateView,
          );
        },
      ),
    ]);
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

List<_NavItem> _navItems(AppLocalizations l) => [
      _NavItem(Icons.download_rounded, l.navDownloads),
      _NavItem(Icons.bar_chart_rounded, l.navStats),
      _NavItem(Icons.settings_outlined, l.navSettings),
    ];

/// Floating rounded navigation bar with an accent "pill" for the active item.
class _PillNav extends StatelessWidget {
  const _PillNav({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final items = _navItems(l);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: z.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: z.outline),
        ),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                flex: i == index ? 2 : 1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(26),
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: i == index ? z.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(items[i].icon,
                            color: i == index ? z.onAccent : z.textMuted, size: 22),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: i == index ? z.onAccent : z.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.compact, required this.tab, required this.onTab});

  final bool compact;
  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final items = _navItems(l);

    return Container(
      width: compact ? 72 : 244,
      color: z.surface,
      child: BlocBuilder<DownloadsCubit, DownloadsState>(
        builder: (context, state) {
          final cubit = context.read<DownloadsCubit>();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
                child: Row(
                  mainAxisAlignment:
                      compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    const ZapLogo(size: 36),
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      Text(l.appName, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ],
                ),
              ),
              for (var i = 0; i < items.length; i++)
                _SidebarTile(
                  icon: items[i].icon,
                  label: items[i].label,
                  selected: tab == i,
                  compact: compact,
                  onTap: () => onTab(i),
                ),
              if (!compact) ...[
                const Divider(height: 24),
                for (final f in StatusFilter.values)
                  _SidebarTile(
                    icon: switch (f) {
                      StatusFilter.all => Icons.list_alt_rounded,
                      StatusFilter.active => Icons.downloading_rounded,
                      StatusFilter.completed => Icons.check_circle_outline_rounded,
                      StatusFilter.failed => Icons.error_outline_rounded,
                    },
                    label: switch (f) {
                      StatusFilter.all => l.statusAll,
                      StatusFilter.active => l.statusDownloading,
                      StatusFilter.completed => l.statusCompleted,
                      StatusFilter.failed => l.statusFailed,
                    },
                    count: state.countFor(f),
                    selected: tab == 0 && state.filter == f,
                    compact: false,
                    onTap: () {
                      cubit.setFilter(f);
                      onTab(0);
                    },
                  ),
                const Divider(height: 24),
                for (final c in <FileCategory?>[null, ...FileCategory.values])
                  _SidebarTile(
                    icon: c == null ? Icons.folder_outlined : categoryIcon(c),
                    label: categoryLabel(l, c),
                    count: state.countForCategory(c),
                    selected: tab == 0 && state.category == c,
                    compact: false,
                    onTap: () {
                      cubit.setCategory(c);
                      onTab(0);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    final fg = selected ? z.accent : z.textMuted;
    final content = Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? z.accentContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(ZapRadii.input - 2),
      ),
      child: Row(
        mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          if (!compact) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? z.accent : z.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (count != null)
              Text(
                formatInt(count!, Localizations.localeOf(context).toString()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ],
      ),
    );
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(ZapRadii.input - 2),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
