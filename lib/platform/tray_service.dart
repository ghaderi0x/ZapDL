import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayLabels {
  const TrayLabels({required this.show, required this.quit, required this.tooltip});
  final String show;
  final String quit;
  final String tooltip;
}

/// Desktop tray icon and close-to-tray behavior.
///
/// While [closeToTray] returns true, closing the window hides it and downloads
/// keep running. "Quit" from the tray menu calls [onQuit], which the app uses
/// to shut the engine down cleanly before the process exits.
class TrayService with TrayListener, WindowListener {
  TrayService({
    required this.closeToTray,
    required this.onQuit,
    required this.labels,
  });

  final bool Function() closeToTray;
  final Future<void> Function() onQuit;
  TrayLabels Function() labels;
  bool _started = false;

  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> start() async {
    if (!supported || _started) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      trayManager.addListener(this);
      await trayManager.setIcon(Platform.isWindows ? 'assets/tray/tray.ico' : 'assets/tray/tray.png');
      await refreshMenu();
      _started = true;
    } catch (e) {
      debugPrint('Tray unavailable: $e');
      // Without a tray, closing the window must really quit (otherwise the
      // user could not reach the app at all).
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}
    }
  }

  Future<void> refreshMenu() async {
    if (!_started && !supported) return;
    try {
      final l = labels();
      await trayManager.setToolTip(l.tooltip);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: l.show),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: l.quit),
      ]));
    } catch (_) {}
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() async {
    if (closeToTray()) {
      await windowManager.hide();
    } else {
      await onQuit();
    }
  }

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') showWindow();
    if (menuItem.key == 'quit') onQuit();
  }

  Future<void> dispose() async {
    if (!_started) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
  }
}
