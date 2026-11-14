import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/format.dart';
import '../../core/quit.dart';
import '../../core/theme/zap_colors.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets.dart';
import '../../update/update_cubit.dart';
import '../../update/update_service.dart';
import 'settings_cubit.dart';

const repoUrl = 'https://github.com/ghaderi0x/ZapDL';

String updateErrorText(AppLocalizations l, String? code) => switch (code) {
      'rateLimited' => l.updateErrRateLimit,
      'network' => l.updateErrNetwork,
      'checksum' => l.updateErrChecksum,
      'noAsset' => l.updateErrNoAsset,
      'unsupported' => l.updateErrUnsupported,
      'install' => l.updateErrInstall,
      'download' => l.updateErrDownload,
      _ => l.updateErrGeneric,
    };

Future<void> openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Update check, download, install and "install from file".
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  Future<void> _check(BuildContext context) {
    final s = context.read<SettingsCubit>().state;
    return context.read<UpdateCubit>().check(
          includePrereleases: s.betaChannel,
          force: true,
          skipped: null,
        );
  }

  Future<void> _install(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await context.read<UpdateCubit>().install();
    if (outcome == InstallOutcome.launchedExit) {
      messenger.showSnackBar(SnackBar(content: Text(l.updateRestarting)));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await quitApp();
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final cubit = context.read<UpdateCubit>();
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path != null) await cubit.useLocalFile(File(path));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (isStoreBuild) {
      return ZapCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.settingsUpdates, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l.updateViaStore),
          ],
        ),
      );
    }
    final z = context.zap;
    final locale = Localizations.localeOf(context).toString();
    final settings = context.read<SettingsCubit>();
    final cubit = context.read<UpdateCubit>();

    return BlocBuilder<UpdateCubit, UpdateState>(
      builder: (context, u) {
        final rel = u.release;
        final busy = u.phase == UpdatePhase.checking ||
            u.phase == UpdatePhase.downloading ||
            u.phase == UpdatePhase.installing;
        return ZapCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.settingsUpdates, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(
                    '${l.aboutVersion}: ${cubit.current}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : () => _check(context),
                  child: u.phase == UpdatePhase.checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.updateCheckNow),
                ),
              ]),
              if (u.checkedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l.updateLastChecked(formatDateTime(u.checkedAt!, locale)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),

              if (u.phase == UpdatePhase.upToDate)
                _Line(icon: Icons.check_circle_outline_rounded, color: z.success, text: l.updateUpToDate),

              if (u.phase == UpdatePhase.error)
                _Line(
                  icon: Icons.error_outline_rounded,
                  color: z.error,
                  text: updateErrorText(l, u.errorCode),
                ),

              if ((u.phase == UpdatePhase.available ||
                      u.phase == UpdatePhase.downloading ||
                      (u.phase == UpdatePhase.ready && u.localNote == null) ||
                      u.phase == UpdatePhase.installing ||
                      (u.phase == UpdatePhase.error && rel != null)) &&
                  rel != null) ...[
                _Line(
                  icon: Icons.system_update_alt_rounded,
                  color: z.accent,
                  text: l.updateAvailable(rel.version.toString()),
                ),
                if (rel.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(l.updateWhatsNew, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        rel.notes.trim(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],

              if (u.phase == UpdatePhase.downloading) ...[
                LinearProgressIndicator(value: u.progress),
                const SizedBox(height: 4),
                Text(
                  u.speed > 0
                      ? '${u.progress == null ? '' : formatPercent(u.progress!, locale)} · ${formatSpeed(u.speed, locale)}'
                      : (u.progress == null ? '' : formatPercent(u.progress!, locale)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                TextButton(onPressed: cubit.cancelDownload, child: Text(l.updateCancel)),
              ],

              if (u.phase == UpdatePhase.ready) ...[
                if (u.localNote != null)
                  _Line(
                    icon: Icons.insert_drive_file_outlined,
                    color: z.accent,
                    text: switch (u.localNote) {
                      'newer' => l.updateLocalNewer,
                      'older' => l.updateLocalOlder,
                      'same' => l.updateLocalSame,
                      _ => l.updateLocalUnknown,
                    },
                  ),
                _Line(
                  icon: u.verified ? Icons.verified_outlined : Icons.info_outline_rounded,
                  color: u.verified ? z.success : z.warning,
                  text: u.verified ? l.updateVerified : l.updateNotVerified,
                ),
                if (u.outcome == InstallOutcome.revealed)
                  Text(l.updateInstallManually, style: Theme.of(context).textTheme.bodySmall),
                if (u.outcome == InstallOutcome.openedForUser)
                  Text(l.updateFollowSystem, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
              ],

              Wrap(spacing: 8, runSpacing: 8, children: [
                if (u.phase == UpdatePhase.available || (u.phase == UpdatePhase.error && rel != null && u.asset != null))
                  if (u.asset != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: Text(l.updateDownload),
                      onPressed: cubit.download,
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(l.updateOpenReleasePage),
                      onPressed: () => openUrl(rel?.pageUrl.isNotEmpty == true ? rel!.pageUrl : '$repoUrl/releases'),
                    ),
                if (u.phase == UpdatePhase.ready)
                  FilledButton.icon(
                    icon: const Icon(Icons.system_update_rounded),
                    label: Text(l.updateInstall),
                    onPressed: () => _install(context),
                  ),
                if (u.phase == UpdatePhase.available && rel != null)
                  TextButton(
                    onPressed: () {
                      settings.skipVersion(rel.version.toString());
                      cubit.dismiss();
                    },
                    child: Text(l.updateSkip),
                  ),
                if (!Platform.isIOS)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(l.updateFromFile),
                    onPressed: busy ? null : () => _pickFile(context),
                  ),
                TextButton(
                  onPressed: () => openUrl('$repoUrl/releases'),
                  child: Text(l.updateAllReleases),
                ),
              ]),
              const Divider(height: 24),
              BlocBuilder<SettingsCubit, SettingsState>(
                buildWhen: (a, b) =>
                    a.autoCheckUpdates != b.autoCheckUpdates || a.betaChannel != b.betaChannel,
                builder: (context, s) => Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.updateAuto),
                    subtitle: Text(l.updateAutoDesc),
                    value: s.autoCheckUpdates,
                    onChanged: settings.setAutoCheckUpdates,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.updateBeta),
                    subtitle: Text(l.updateBetaDesc),
                    value: s.betaChannel,
                    onChanged: settings.setBetaChannel,
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}
