import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/accent_palette.dart';
import '../../engine/engine.dart';
import '../../engine/http_support.dart';
import '../../engine/models.dart';

const supportedLanguageCodes = ['en', 'fa', 'ar', 'es', 'zh', 'ru'];

/// Native language names (never translated, so users can always find theirs).
const languageNames = {
  'en': 'English',
  'fa': 'فارسی',
  'ar': 'العربية',
  'es': 'Español',
  'zh': '中文',
  'ru': 'Русский',
};

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.palette,
    required this.languageCode,
    required this.downloadDir,
    required this.maxConcurrent,
    required this.connections,
    required this.speedLimitKb,
    required this.onboardingDone,
    this.wifiOnly = false,
    this.proxyMode = ProxyMode.system,
    this.proxyHost = '',
    this.proxyPort = 0,
    this.proxyUsername = '',
    this.proxyPassword = '',
    this.scheduleEnabled = false,
    this.scheduleStartMinute = 23 * 60,
    this.scheduleEndMinute = 6 * 60,
    this.closeToTray = true,
    this.notificationsEnabled = true,
    this.autoCheckUpdates = true,
    this.betaChannel = false,
    this.skippedVersion,
  });

  final ThemeMode themeMode;
  final AccentPalette palette;

  /// null = follow system language.
  final String? languageCode;
  final String downloadDir;
  final int maxConcurrent;
  final int connections;

  /// KiB/s per download; 0 = unlimited.
  final int speedLimitKb;
  final bool onboardingDone;

  /// Mobile data is not used for downloads while true.
  final bool wifiOnly;
  final ProxyMode proxyMode;
  final String proxyHost;
  final int proxyPort;

  /// Proxy credentials live in secure storage, not in preferences.
  final String proxyUsername;
  final String proxyPassword;

  /// Downloads only run between [scheduleStartMinute] and [scheduleEndMinute].
  final bool scheduleEnabled;
  final int scheduleStartMinute;
  final int scheduleEndMinute;

  /// Desktop: closing the window keeps ZapDL running in the tray.
  final bool closeToTray;
  final bool notificationsEnabled;
  final bool autoCheckUpdates;

  /// Also offer pre-releases (beta versions).
  final bool betaChannel;

  /// A release the user chose to ignore.
  final String? skippedVersion;

  ProxyConfig get proxy => ProxyConfig(
        mode: proxyMode,
        host: proxyHost,
        port: proxyPort,
        username: proxyUsername.isEmpty ? null : proxyUsername,
        password: proxyPassword.isEmpty ? null : proxyPassword,
      );

  DailyWindow? get window => scheduleEnabled
      ? DailyWindow(startMinute: scheduleStartMinute, endMinute: scheduleEndMinute)
      : null;

  Locale? get locale => languageCode == null ? null : Locale(languageCode!);

  SettingsState copyWith({
    ThemeMode? themeMode,
    AccentPalette? palette,
    String? languageCode,
    bool clearLanguage = false,
    String? downloadDir,
    int? maxConcurrent,
    int? connections,
    int? speedLimitKb,
    bool? onboardingDone,
    bool? wifiOnly,
    ProxyMode? proxyMode,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    bool? scheduleEnabled,
    int? scheduleStartMinute,
    int? scheduleEndMinute,
    bool? closeToTray,
    bool? notificationsEnabled,
    bool? autoCheckUpdates,
    bool? betaChannel,
    String? skippedVersion,
    bool clearSkippedVersion = false,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        palette: palette ?? this.palette,
        languageCode: clearLanguage ? null : (languageCode ?? this.languageCode),
        downloadDir: downloadDir ?? this.downloadDir,
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
        connections: connections ?? this.connections,
        speedLimitKb: speedLimitKb ?? this.speedLimitKb,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        proxyMode: proxyMode ?? this.proxyMode,
        proxyHost: proxyHost ?? this.proxyHost,
        proxyPort: proxyPort ?? this.proxyPort,
        proxyUsername: proxyUsername ?? this.proxyUsername,
        proxyPassword: proxyPassword ?? this.proxyPassword,
        scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
        scheduleStartMinute: scheduleStartMinute ?? this.scheduleStartMinute,
        scheduleEndMinute: scheduleEndMinute ?? this.scheduleEndMinute,
        closeToTray: closeToTray ?? this.closeToTray,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
        betaChannel: betaChannel ?? this.betaChannel,
        skippedVersion:
            clearSkippedVersion ? null : (skippedVersion ?? this.skippedVersion),
      );

  @override
  List<Object?> get props => [
        themeMode,
        palette.serialize(),
        languageCode,
        downloadDir,
        maxConcurrent,
        connections,
        speedLimitKb,
        onboardingDone,
        wifiOnly,
        proxyMode,
        proxyHost,
        proxyPort,
        proxyUsername,
        proxyPassword,
        scheduleEnabled,
        scheduleStartMinute,
        scheduleEndMinute,
        closeToTray,
        notificationsEnabled,
        autoCheckUpdates,
        betaChannel,
        skippedVersion,
      ];
}

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(
    this._prefs,
    this._engine,
    String defaultDir, {
    SecretStore? secureStore,
  })  : _secure = secureStore,
        super(_load(_prefs, defaultDir)) {
    _applyToEngine();
  }

  static const _proxySecretId = '__proxy__';

  final SharedPreferences _prefs;
  final DownloadEngine _engine;
  final SecretStore? _secure;

  /// Loads the proxy credentials from secure storage. Call once at startup.
  Future<void> loadSecrets() async {
    final store = _secure;
    if (store == null) return;
    try {
      final s = await store.read(_proxySecretId);
      emit(state.copyWith(
        proxyUsername: s['username'] ?? '',
        proxyPassword: s['password'] ?? '',
      ));
      _applyToEngine();
    } catch (_) {
      // Secure storage unavailable: the proxy simply runs without credentials.
    }
  }

  static SettingsState _load(SharedPreferences p, String defaultDir) {
    final modeName = p.getString('themeMode');
    final lang = p.getString('language');
    return SettingsState(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => ThemeMode.system,
      ),
      palette: AccentPalette.deserialize(p.getString('accent')),
      languageCode: supportedLanguageCodes.contains(lang) ? lang : null,
      downloadDir: p.getString('downloadDir') ?? defaultDir,
      maxConcurrent: (p.getInt('maxConcurrent') ?? 3).clamp(1, 8),
      connections: (p.getInt('connections') ?? 4).clamp(1, 16),
      speedLimitKb: p.getInt('speedLimitKb') ?? 0,
      onboardingDone: p.getBool('onboardingDone') ?? false,
      wifiOnly: p.getBool('wifiOnly') ?? false,
      proxyMode: ProxyMode.values.firstWhere(
        (m) => m.name == p.getString('proxyMode'),
        orElse: () => ProxyMode.system,
      ),
      proxyHost: p.getString('proxyHost') ?? '',
      proxyPort: p.getInt('proxyPort') ?? 0,
      scheduleEnabled: p.getBool('scheduleEnabled') ?? false,
      scheduleStartMinute: (p.getInt('scheduleStart') ?? 23 * 60).clamp(0, 1439),
      scheduleEndMinute: (p.getInt('scheduleEnd') ?? 6 * 60).clamp(0, 1439),
      closeToTray: p.getBool('closeToTray') ?? true,
      notificationsEnabled: p.getBool('notifications') ?? true,
      autoCheckUpdates: p.getBool('autoCheckUpdates') ?? true,
      betaChannel: p.getBool('betaChannel') ?? false,
      skippedVersion: p.getString('skippedVersion'),
    );
  }

  void _applyToEngine() {
    _engine.config
      ..maxConcurrent = state.maxConcurrent
      ..connections = state.connections
      ..speedLimitBps = state.speedLimitKb * 1024
      ..proxy = state.proxy
      ..allowedWindow = state.window;
    _engine.configChanged();
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setString('themeMode', mode.name);
    emit(state.copyWith(themeMode: mode));
  }

  void setPalette(AccentPalette palette) {
    _prefs.setString('accent', palette.serialize());
    emit(state.copyWith(palette: palette));
  }

  void setLanguage(String? code) {
    if (code == null) {
      _prefs.remove('language');
      emit(state.copyWith(clearLanguage: true));
    } else {
      _prefs.setString('language', code);
      emit(state.copyWith(languageCode: code));
    }
  }

  void setDownloadDir(String dir) {
    _prefs.setString('downloadDir', dir);
    emit(state.copyWith(downloadDir: dir));
  }

  void setMaxConcurrent(int v) {
    _prefs.setInt('maxConcurrent', v);
    emit(state.copyWith(maxConcurrent: v));
    _applyToEngine();
  }

  void setConnections(int v) {
    _prefs.setInt('connections', v);
    emit(state.copyWith(connections: v));
    _applyToEngine();
  }

  void setSpeedLimitKb(int v) {
    _prefs.setInt('speedLimitKb', v);
    emit(state.copyWith(speedLimitKb: v));
    _applyToEngine();
  }

  void completeOnboarding() {
    _prefs.setBool('onboardingDone', true);
    emit(state.copyWith(onboardingDone: true));
  }

  void setWifiOnly(bool v) {
    _prefs.setBool('wifiOnly', v);
    emit(state.copyWith(wifiOnly: v));
  }

  /// Saves the proxy. The password goes to secure storage; host and port are
  /// ordinary preferences. An invalid manual proxy is rejected by the caller
  /// via [ProxyConfig.isManualValid] before this is called.
  Future<void> setProxy({
    required ProxyMode mode,
    String host = '',
    int port = 0,
    String username = '',
    String password = '',
  }) async {
    await _prefs.setString('proxyMode', mode.name);
    await _prefs.setString('proxyHost', host);
    await _prefs.setInt('proxyPort', port);
    emit(state.copyWith(
      proxyMode: mode,
      proxyHost: host,
      proxyPort: port,
      proxyUsername: username,
      proxyPassword: password,
    ));
    _applyToEngine();
    final store = _secure;
    if (store != null) {
      try {
        await store.write(_proxySecretId, {
          if (username.isNotEmpty) 'username': username,
          if (password.isNotEmpty) 'password': password,
        });
      } catch (_) {}
    }
  }

  void setSchedule({required bool enabled, int? startMinute, int? endMinute}) {
    _prefs.setBool('scheduleEnabled', enabled);
    if (startMinute != null) _prefs.setInt('scheduleStart', startMinute);
    if (endMinute != null) _prefs.setInt('scheduleEnd', endMinute);
    emit(state.copyWith(
      scheduleEnabled: enabled,
      scheduleStartMinute: startMinute,
      scheduleEndMinute: endMinute,
    ));
    _applyToEngine();
  }

  void setCloseToTray(bool v) {
    _prefs.setBool('closeToTray', v);
    emit(state.copyWith(closeToTray: v));
  }

  void setNotifications(bool v) {
    _prefs.setBool('notifications', v);
    emit(state.copyWith(notificationsEnabled: v));
  }

  void setAutoCheckUpdates(bool v) {
    _prefs.setBool('autoCheckUpdates', v);
    emit(state.copyWith(autoCheckUpdates: v));
  }

  void setBetaChannel(bool v) {
    _prefs.setBool('betaChannel', v);
    emit(state.copyWith(betaChannel: v));
  }

  void skipVersion(String? version) {
    if (version == null) {
      _prefs.remove('skippedVersion');
      emit(state.copyWith(clearSkippedVersion: true));
    } else {
      _prefs.setString('skippedVersion', version);
      emit(state.copyWith(skippedVersion: version));
    }
  }
}
