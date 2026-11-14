import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'platform/single_instance.dart';
import 'platform/tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // One process only: opening ZapDL again (for example after closing the
  // window to the tray) must show the running window, not start a second app.
  if (TrayService.supported) {
    final first = await SingleInstance.acquire(onActivate: () async {
      try {
        await windowManager.ensureInitialized();
        if (await windowManager.isMinimized()) await windowManager.restore();
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    });
    if (!first) exit(0);
  }
  // Makes the bundled-font licenses appear in Settings > About > Licenses.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/LICENSES.txt');
    yield LicenseEntryWithLineBreaks(['Vazirmatn', 'Inter', 'Noto Sans SC'], text);
  });
  runApp(const Bootstrap());
}
