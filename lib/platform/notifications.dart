import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

/// Shows local notifications. Implementations never throw: a notification that
/// cannot be shown must not break a download.
abstract class AppNotifier {
  Future<void> init({required String appName});
  Future<void> show({required String id, required String title, required String body});
}

class NoopNotifier implements AppNotifier {
  @override
  Future<void> init({required String appName}) async {}
  @override
  Future<void> show({required String id, required String title, required String body}) async {}
}

/// flutter_local_notifications on mobile, local_notifier on desktop.
class PlatformNotifier implements AppNotifier {
  final FlutterLocalNotificationsPlugin _mobile = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _next = 1000;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Future<void> init({required String appName}) async {
    try {
      if (_isMobile) {
        await _mobile.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ));
        // Android 13+ and iOS ask the user here; a refusal just means no notifications.
        await _mobile
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        await _mobile
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, sound: true);
      } else {
        await localNotifier.setup(appName: appName);
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  @override
  Future<void> show({required String id, required String title, required String body}) async {
    if (!_ready) return;
    try {
      if (_isMobile) {
        await _mobile.show(
          _next++,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'zapdl_events',
              'Download events',
              importance: Importance.defaultImportance,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      } else {
        await LocalNotification(identifier: id, title: title, body: body).show();
      }
    } catch (_) {}
  }
}
