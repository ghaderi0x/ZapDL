import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../core/format.dart';
import '../../core/platform.dart';
import '../../core/theme/accent_palette.dart';
import 'theme_picker.dart';
import '../../core/theme/zap_colors.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets.dart';
import '../../core/app_info.dart';
import '../downloads/downloads_cubit.dart';
import '../downloads/url_history.dart';
import 'network_settings.dart';
import 'settings_cubit.dart';
import 'updates_section.dart';

const _speedLimitOptionsKb = [0, 256, 1024, 5 * 1024, 20 * 1024];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    final locale = Localizations.localeOf(context).toString();

    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, s) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.navSettings, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),

            // ---- Appearance
            _Section(
              title: l.settingsAppearance,
              children: [
                const ThemePicker(),
                const SizedBox(height: 16),
                Text(l.accentColor, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final p in AccentPalette.presets)
                      _Swatch(
                        color: p.primary,
                        selected: s.palette.id == p.id,
                        onTap: () => cubit.setPalette(p),
                      ),
                    _Swatch(
                      color: s.palette.id == 'custom' ? s.palette.primary : null,
                      selected: s.palette.id == 'custom',
                      icon: Icons.colorize_rounded,
                      tooltip: l.customColor,
                      onTap: () => _pickCustomColor(context, s.palette.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l.language, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: s.languageCode,
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.languageSystem)),
                    for (final code in supportedLanguageCodes)
                      DropdownMenuItem(value: code, child: Text(languageNames[code]!)),
                  ],
                  onChanged: cubit.setLanguage,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Downloads
            _Section(
              title: l.settingsDownloads,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.downloadFolder, style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 2),
                        Text(s.downloadDir,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (isDesktopPlatform)
                    TextButton(
                      onPressed: () async {
                        final dir = await FilePicker.platform.getDirectoryPath();
                        if (dir != null) cubit.setDownloadDir(dir);
                      },
                      child: Text(l.actionChange),
                    ),
                ]),
                const SizedBox(height: 8),
                _SliderRow(
                  label: l.maxConcurrent,
                  value: s.maxConcurrent,
                  min: 1,
                  max: 8,
                  onChanged: cubit.setMaxConcurrent,
                ),
                _SliderRow(
                  label: l.connectionsPer,
                  value: s.connections,
                  min: 1,
                  max: 16,
                  onChanged: cubit.setConnections,
                ),
                const SizedBox(height: 8),
                Text(l.speedLimitPer, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _speedLimitOptionsKb.contains(s.speedLimitKb) ? s.speedLimitKb : 0,
                  items: [
                    for (final kb in _speedLimitOptionsKb)
                      DropdownMenuItem(
                        value: kb,
                        child: Text(kb == 0 ? l.speedLimitNone : formatSpeed(kb * 1024, locale)),
                      ),
                  ],
                  onChanged: (v) => cubit.setSpeedLimitKb(v ?? 0),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const NetworkSection(),
            const SizedBox(height: 16),
            const ScheduleSection(),
            const SizedBox(height: 16),
            const BackgroundSection(),
            const SizedBox(height: 16),
            const UpdatesSection(),
            const SizedBox(height: 16),

            // ---- Advanced
            _Section(
              title: l.settingsAdvanced,
              children: [
                _ActionRow(
                  icon: Icons.cleaning_services_outlined,
                  title: l.cleanTempTitle,
                  subtitle: l.cleanTempBody,
                  onTap: () async {
                    final freed = await context.read<DownloadsCubit>().cleanTempFiles();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.cleanTempDone(formatBytes(freed, locale)))),
                    );
                  },
                ),
                _ActionRow(
                  icon: Icons.history_toggle_off_rounded,
                  title: l.clearLinkHistory,
                  onTap: () async {
                    await context.read<UrlHistory>().clear();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.linkHistoryCleared)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- About
            _Section(
              title: l.settingsAbout,
              children: [
                Row(children: [
                  const ZapLogo(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.appName, style: Theme.of(context).textTheme.titleMedium),
                        Text(l.tagline, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(l.aboutNote, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Row(children: [
                  Text(l.aboutVersion, style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  Text(appVersion, style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(l.aboutLicense, style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  Text(appLicense, style: Theme.of(context).textTheme.bodyMedium),
                ]),
                const SizedBox(height: 8),
                _ActionRow(
                  icon: Icons.code_rounded,
                  title: l.aboutGithub,
                  subtitle: repoUrl,
                  onTap: () => openUrl(repoUrl),
                ),
                _ActionRow(
                  icon: Icons.bug_report_outlined,
                  title: l.aboutReportIssue,
                  onTap: () => openUrl('$repoUrl/issues/new/choose'),
                ),
                _ActionRow(
                  icon: Icons.description_outlined,
                  title: l.aboutThirdParty,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: l.appName,
                    applicationVersion: appVersion,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickCustomColor(BuildContext context, Color current) async {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    var picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pickColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: current,
            onColorChanged: (c) => picked = c,
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.actionClose)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.actionApply)),
        ],
      ),
    );
    if (ok == true) cubit.setPalette(AccentPalette.fromColor(picked));
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconTile(icon: icon, size: 40),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: onTap,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ZapCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tooltip,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    final bg = color ?? z.surfaceRaised;
    final fg = color == null ? z.textMuted : (bg.computeLuminance() > 0.5 ? Colors.black : Colors.white);
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? z.text : z.outline,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: fg, size: 20)
              : (icon != null ? Icon(icon, color: fg, size: 18) : null),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    return Row(children: [
      Expanded(flex: 3, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Expanded(
        flex: 3,
        child: Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
      SizedBox(
        width: 28,
        child: Text(formatInt(value, locale), textAlign: TextAlign.end),
      ),
    ]);
  }
}
