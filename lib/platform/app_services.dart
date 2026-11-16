import 'dart:async';

import 'package:flutter/widgets.dart';

import '../engine/engine.dart';
import '../engine/models.dart';
import '../features/settings/settings_cubit.dart';
import 'background_service.dart';
import 'network_policy.dart';
import 'notifications.dart';

/// Localized texts used outside the widget tree (notifications). The app
/// builds these from AppLocalizations for the current language.
class ServiceTexts {
  const ServiceTexts({
    required this.appName,
    required this.completed,
    required this.failed,
    required this.ongoing,
  });

  final String appName;

  /// Title for a finished download; the body is the file name.
  final String completed;
  final String failed;

  /// Body of the ongoing notification: (activeCount, totalSpeedBytesPerSecond).
  final String Function(int active, double bytesPerSecond) ongoing;
}

/// Glue between the engine and the platform: network policy (Wi-Fi only,
/// offline), notifications, the Android foreground service and the iOS
/// suspend/resume cycle. All dependencies are injected so it can be tested
/// without a device.
class AppServices with WidgetsBindingObserver {
  AppServices({
    required this.engine,
    required this.settings,
    required this.network,
    required this.notifier,
    required this.background,
    required this.texts,
    this.suspendOnPause = false,
    this.backgroundThrottle = const Duration(seconds: 2),
  });

  final DownloadEngine engine;
  final SettingsCubit settings;
  final NetworkSource network;
  final AppNotifier notifier;
  final BackgroundService background;
  final ServiceTexts Function() texts;

  /// True on iOS, where the app cannot run in the background.
  final bool suspendOnPause;
  final Duration backgroundThrottle;

  final Map<String, DownloadStatus> _last = {};
  StreamSubscription<List<DownloadTask>>? _engineSub;
  StreamSubscription<Set<ConnectionKind>>? _netSub;
  StreamSubscription<SettingsState>? _settingsSub;
  Set<ConnectionKind> _kinds = {ConnectionKind.other};
  bool _networkWasAllowed = true;
  bool _wifiOnly = false;
  bool _started = false;
  DateTime _lastBackgroundUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _backgroundShown = false;

  /// Connection kinds as last seen (for UI hints like "on mobile data").
  Set<ConnectionKind> get connections => _kinds;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await notifier.init(appName: texts().appName);
    for (final t in engine.snapshot) {
      _last[t.id] = t.status;
    }
    _wifiOnly = settings.state.wifiOnly;
    _kinds = await network.current();
    _applyNetwork();

    _netSub = network.changes.listen((k) {
      _kinds = k;
      _applyNetwork();
    });
    _settingsSub = settings.stream.listen((s) {
      if (s.wifiOnly != _wifiOnly) {
        _wifiOnly = s.wifiOnly;
        _applyNetwork();
      }
    });
    _engineSub = engine.updates.listen(_onTasks);
    WidgetsBinding.instance.addObserver(this);
  }

  void _applyNetwork() {
    final allowed = transfersAllowed(_kinds, wifiOnly: _wifiOnly);
    engine.setNetworkAllowed(allowed);
    // Connectivity came back: retry downloads that failed only for lack of it.
    if (allowed && !_networkWasAllowed) engine.retryNetworkFailures();
    _networkWasAllowed = allowed;
  }

  void _onTasks(List<DownloadTask> tasks) {
    final t = texts();
    var active = 0;
    var speed = 0.0;
    var got = 0;
    var total = 0;
    for (final task in tasks) {
      final before = _last[task.id];
      if (task.status == DownloadStatus.downloading) {
        active++;
        speed += task.speedBps;
        if (task.totalBytes > 0) {
          got += task.receivedBytes;
          total += task.totalBytes;
        }
      }
      if (before != null && before != task.status) {
        if (task.status == DownloadStatus.completed) {
          _notify(task.id, t.completed, task.fileName);
        } else if (task.status == DownloadStatus.failed) {
          _notify(task.id, t.failed, task.fileName);
        }
      }
      _last[task.id] = task.status;
    }
    _last.removeWhere((id, _) => !tasks.any((x) => x.id == id));
    _updateBackground(active, speed, t, total > 0 ? (got * 100 ~/ total).clamp(0, 100) : null);
  }

  void _notify(String id, String title, String body) {
    if (!settings.state.notificationsEnabled) return;
    notifier.show(id: id, title: title, body: body);
  }

  void _updateBackground(int active, double speed, ServiceTexts t, int? progress) {
    if (active == 0) {
      if (_backgroundShown) {
        _backgroundShown = false;
        background.stop();
      }
      return;
    }
    final now = DateTime.now();
    if (_backgroundShown && now.difference(_lastBackgroundUpdate) < backgroundThrottle) {
      return;
    }
    _lastBackgroundUpdate = now;
    _backgroundShown = true;
    background.update(
      title: t.appName,
      text: t.ongoing(active, speed),
      progress: progress,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!suspendOnPause) return;
    // iOS suspends the process soon after this: park downloads so they restart
    // cleanly (with Range resume) when the app comes back.
    if (state == AppLifecycleState.paused) engine.setSuspended(true);
    if (state == AppLifecycleState.resumed) engine.setSuspended(false);
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _engineSub?.cancel();
    await _netSub?.cancel();
    await _settingsSub?.cancel();
    await background.stop();
  }
}
