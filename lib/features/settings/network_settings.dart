import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform.dart';
import '../../core/theme/zap_colors.dart';
import '../../engine/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets.dart';
import 'settings_cubit.dart';

/// Wi-Fi-only mode and proxy.
class NetworkSection extends StatefulWidget {
  const NetworkSection({super.key});

  @override
  State<NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<NetworkSection> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  late ProxyMode _mode;
  bool _invalid = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsCubit>().state;
    _mode = s.proxyMode;
    _host = TextEditingController(text: s.proxyHost);
    _port = TextEditingController(text: s.proxyPort == 0 ? '' : '${s.proxyPort}');
    _user = TextEditingController(text: s.proxyUsername);
    _pass = TextEditingController(text: s.proxyPassword);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cubit = context.read<SettingsCubit>();
    final port = int.tryParse(_port.text.trim()) ?? 0;
    final cfg = ProxyConfig(
      mode: _mode,
      host: _host.text.trim(),
      port: port,
      username: _user.text,
      password: _pass.text,
    );
    if (_mode == ProxyMode.manual && !cfg.isManualValid) {
      setState(() {
        _invalid = true;
        _saved = false;
      });
      return;
    }
    await cubit.setProxy(
      mode: _mode,
      host: _mode == ProxyMode.manual ? cfg.host : '',
      port: _mode == ProxyMode.manual ? port : 0,
      username: _mode == ProxyMode.manual ? _user.text : '',
      password: _mode == ProxyMode.manual ? _pass.text : '',
    );
    if (mounted) {
      setState(() {
        _invalid = false;
        _saved = true;
      });
    }
  }

  String _modeLabel(AppLocalizations l, ProxyMode m) => switch (m) {
        ProxyMode.system => l.proxySystem,
        ProxyMode.none => l.proxyNone,
        ProxyMode.manual => l.proxyManual,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    final z = context.zap;
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (a, b) => a.wifiOnly != b.wifiOnly,
      builder: (context, s) => ZapCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.settingsNetwork, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsWifiOnly),
              subtitle: Text(l.settingsWifiOnlyDesc),
              value: s.wifiOnly,
              onChanged: cubit.setWifiOnly,
            ),
            const Divider(),
            const SizedBox(height: 8),
            Text(l.settingsProxy, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            DropdownButtonFormField<ProxyMode>(
              initialValue: _mode,
              items: [
                for (final m in ProxyMode.values)
                  DropdownMenuItem(value: m, child: Text(_modeLabel(l, m))),
              ],
              onChanged: (m) => setState(() {
                _mode = m ?? ProxyMode.system;
                _saved = false;
                _invalid = false;
              }),
            ),
            if (_mode == ProxyMode.manual) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(labelText: l.proxyHost),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.proxyPort),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _user,
                    decoration: InputDecoration(labelText: l.proxyUser),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l.proxyPass),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(l.proxyHttpOnly, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_invalid)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l.errProxy, style: TextStyle(color: z.error)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton(onPressed: _save, child: Text(l.actionSave)),
              if (_saved) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_circle_outline_rounded, color: z.success, size: 18),
                const SizedBox(width: 4),
                Text(l.settingsSaved),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

/// Daily time window for downloads.
class ScheduleSection extends StatelessWidget {
  const ScheduleSection({super.key});

  Future<void> _pick(BuildContext context, SettingsState s, {required bool start}) async {
    final cubit = context.read<SettingsCubit>();
    final minute = start ? s.scheduleStartMinute : s.scheduleEndMinute;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    cubit.setSchedule(
      enabled: s.scheduleEnabled,
      startMinute: start ? m : null,
      endMinute: start ? null : m,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    String fmt(int minute) =>
        TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (a, b) =>
          a.scheduleEnabled != b.scheduleEnabled ||
          a.scheduleStartMinute != b.scheduleStartMinute ||
          a.scheduleEndMinute != b.scheduleEndMinute,
      builder: (context, s) => ZapCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.settingsSchedule, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsScheduleEnable),
              subtitle: Text(l.settingsScheduleDesc),
              value: s.scheduleEnabled,
              onChanged: (v) => cubit.setSchedule(enabled: v),
            ),
            if (s.scheduleEnabled)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('${l.scheduleFrom} ${fmt(s.scheduleStartMinute)}'),
                    onPressed: () => _pick(context, s, start: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('${l.scheduleTo} ${fmt(s.scheduleEndMinute)}'),
                    onPressed: () => _pick(context, s, start: false),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Notifications, tray and platform notes about background downloads.
class BackgroundSection extends StatelessWidget {
  const BackgroundSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cubit = context.read<SettingsCubit>();
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (a, b) =>
          a.notificationsEnabled != b.notificationsEnabled || a.closeToTray != b.closeToTray,
      builder: (context, s) => ZapCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.settingsBackground, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.settingsNotifications),
              value: s.notificationsEnabled,
              onChanged: cubit.setNotifications,
            ),
            if (isDesktopPlatform)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.settingsCloseToTray),
                subtitle: Text(l.settingsCloseToTrayDesc),
                value: s.closeToTray,
                onChanged: cubit.setCloseToTray,
              ),
            const SizedBox(height: 4),
            Text(
              Platform.isAndroid
                  ? l.backgroundNoteAndroid
                  : Platform.isIOS
                      ? l.backgroundNoteIos
                      : l.backgroundNoteDesktop,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
