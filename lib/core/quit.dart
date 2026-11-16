import 'dart:io';

import '../engine/engine.dart';
import 'di.dart';

/// Stops downloads cleanly (progress is saved, running downloads resume at the
/// next start) and exits. Used by the tray's "Quit" and by the updater when
/// an installer needs ZapDL closed.
Future<void> quitApp() async {
  try {
    await getIt<DownloadEngine>().shutdown(keepQueued: true);
  } catch (_) {}
  exit(0);
}
