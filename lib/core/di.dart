import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine/engine.dart';
import '../engine/models.dart';
import '../engine/store.dart';
import '../features/downloads/downloads_cubit.dart';
import '../features/downloads/url_history.dart';
import '../features/settings/settings_cubit.dart';
import '../l10n/gen/app_localizations.dart';
import '../media/resolver.dart';
import '../platform/app_services.dart';
import '../platform/background_service.dart';
import '../platform/incoming_links.dart';
import '../platform/network_policy.dart';
import '../platform/notifications.dart';
import '../platform/share_intake.dart';
import '../platform/tray_service.dart';
import '../update/asset_selector.dart';
import '../update/installer.dart';
import '../update/semver.dart';
import '../update/update_cubit.dart';
import '../update/update_service.dart';
import 'app_info.dart';
import 'format.dart';
import 'logger.dart';
import 'platform.dart';
import 'secure_secret_store.dart';

final getIt = GetIt.instance;

UpdatePlatform get _updatePlatform {
  if (Platform.isAndroid) return UpdatePlatform.android;
  if (Platform.isIOS) return UpdatePlatform.ios;
  if (Platform.isWindows) return UpdatePlatform.windows;
  if (Platform.isMacOS) return UpdatePlatform.macos;
  return UpdatePlatform.linux;
}

/// Localized strings for places outside the widget tree (notifications, tray).
AppLocalizations _l10n(SettingsCubit settings) {
  final wanted = settings.state.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
  final code = supportedLanguageCodes.contains(wanted) ? wanted : 'en';
  return lookupAppLocalizations(Locale(code));
}

/// Wires the app together. The engine is a plain Dart object with no Flutter
/// dependencies; cubits are the only bridge between it and the UI.
Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  final support = await getApplicationSupportDirectory();
  final defaultDir = await defaultDownloadDirectory();

  final logger = AppLogger();
  final secrets = SecureSecretStore();
  final engine = DownloadEngine(
    store: JsonFileDownloadStore(File(p.join(support.path, 'downloads.json'))),
    partsRoot: p.join(support.path, 'parts'),
    logger: logger.info,
    secrets: secrets,
  );
  final settings = SettingsCubit(prefs, engine, defaultDir, secureStore: secrets);
  await settings.loadSecrets();
  // Downloads that were running when the app last exited continue automatically.
  await engine.init(resumeInterrupted: true);

  final resolver = MediaResolver(proxy: settings.state.proxy);
  final incoming = IncomingLinks();
  final updateService = UpdateService(
    prefs: prefs,
    currentVersion: SemVer.tryParse(appVersion)!,
    updatesDir: p.join(support.path, 'updates'),
    platform: _updatePlatform,
    arch: archToken(Platform.version),
    installer: SystemInstaller(),
    proxy: settings.state.proxy,
  );
  final updates = UpdateCubit(updateService);
  final notifier = Platform.isLinux || Platform.isWindows || Platform.isMacOS || isMobilePlatform
      ? PlatformNotifier()
      : NoopNotifier();

  final services = AppServices(
    engine: engine,
    settings: settings,
    network: ConnectivityNetworkSource(),
    notifier: notifier,
    background: Platform.isAndroid ? AndroidForegroundService() : NoopBackgroundService(),
    suspendOnPause: Platform.isIOS,
    texts: () {
      final l = _l10n(settings);
      final code = settings.state.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
      return ServiceTexts(
        appName: 'ZapDL',
        completed: l.notifCompleted,
        failed: l.notifFailed,
        ongoing: (n, speed) => l.notifOngoing(n, formatSpeed(speed, code)),
      );
    },
  );

  final tray = TrayService(
    closeToTray: () => settings.state.closeToTray,
    onQuit: () async {
      await engine.shutdown(keepQueued: true);
      exit(0);
    },
    labels: () {
      final l = _l10n(settings);
      return TrayLabels(show: l.trayShow, quit: l.trayQuit, tooltip: 'ZapDL');
    },
  );

  // The proxy applies to media lookups and update checks as well as downloads.
  settings.stream.listen((s) {
    resolver.proxy = s.proxy;
    updateService.proxy = s.proxy;
    if (TrayService.supported) tray.refreshMenu();
  });

  // Tray menu/tooltip: "N active · speed" while downloading (throttled).
  if (TrayService.supported) {
    var lastTrayUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    engine.updates.listen((tasks) {
      final now = DateTime.now();
      if (now.difference(lastTrayUpdate) < const Duration(seconds: 2)) return;
      lastTrayUpdate = now;
      var active = 0;
      var speed = 0.0;
      for (final t in tasks) {
        if (t.status == DownloadStatus.downloading) {
          active++;
          speed += t.speedBps;
        }
      }
      final l = _l10n(settings);
      final code = settings.state.languageCode ?? PlatformDispatcher.instance.locale.languageCode;
      unawaited(tray.setStatus(active == 0 ? null : l.notifOngoing(active, formatSpeed(speed, code))));
    });
  }

  getIt
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<UrlHistory>(UrlHistory(prefs))
    ..registerSingleton<DownloadEngine>(engine)
    ..registerSingleton<SettingsCubit>(settings)
    ..registerSingleton<MediaResolver>(resolver)
    ..registerSingleton<DownloadsCubit>(DownloadsCubit(engine, resolver: resolver))
    ..registerSingleton<UpdateCubit>(updates)
    ..registerSingleton<IncomingLinks>(incoming)
    ..registerSingleton<AppServices>(services);

  // Platform features start in the background so a missing plugin or a
  // permission prompt can never delay (or break) startup.
  unawaited(services.start());
  if (TrayService.supported) unawaited(tray.start());
  unawaited(ShareIntake().start(incoming.add));
  unawaited(_autoCheckForUpdates(settings, updates, updateService, notifier, prefs));
  Timer.periodic(const Duration(hours: 6), (_) {
    unawaited(_autoCheckForUpdates(settings, updates, updateService, notifier, prefs));
  });
}

/// At most one check per 24 h, silent on failure, one notification per version.
Future<void> _autoCheckForUpdates(
  SettingsCubit settings,
  UpdateCubit updates,
  UpdateService service,
  AppNotifier notifier,
  SharedPreferences prefs,
) async {
  if (isStoreBuild) return; // the store updates the app
  if (!service.autoCheckDue(enabled: settings.state.autoCheckUpdates)) return;
  final rel = await updates.check(
    includePrereleases: settings.state.betaChannel,
    force: false,
    silent: true,
    skipped: settings.state.skippedVersion,
  );
  if (rel == null) return;
  final v = rel.version.toString();
  if (prefs.getString('update.notified') == v) return;
  await prefs.setString('update.notified', v);
  if (!settings.state.notificationsEnabled) return;
  final l = _l10n(settings);
  await notifier.show(
    id: 'update-$v',
    title: l.notifUpdateTitle,
    body: l.notifUpdateBody(v),
  );
}
