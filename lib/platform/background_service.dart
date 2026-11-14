import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps downloads alive while the app is in the background.
///
/// Android: a foreground service with a persistent notification (implemented
/// in Kotlin, installed by `dart tool/setup.dart`).
/// Desktop: the process keeps running; the tray (see tray_service.dart) keeps
/// the window closed but the app alive.
/// iOS: not possible. iOS suspends the app, so downloads pause and resume
/// automatically when it returns (see AppServices).
abstract class BackgroundService {
  /// Shows/updates the ongoing notification. Starts the service if needed.
  Future<void> update({required String title, required String text});
  Future<void> stop();
}

class NoopBackgroundService implements BackgroundService {
  @override
  Future<void> update({required String title, required String text}) async {}
  @override
  Future<void> stop() async {}
}

class AndroidForegroundService implements BackgroundService {
  static const _channel = MethodChannel('dev.zapdl/background');
  bool _running = false;

  @override
  Future<void> update({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('update', {'title': title, 'text': text});
      _running = true;
    } on PlatformException {
      // Android may refuse starting a service from the background; the
      // downloads still run for as long as the OS keeps the process alive.
    } on MissingPluginException {
      // Native side not installed (setup.dart not run).
    }
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid || !_running) return;
    _running = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
