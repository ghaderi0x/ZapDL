import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../core/platform.dart';
import 'asset_selector.dart';
import 'update_service.dart';

/// Hands a verified update file to the operating system.
///
/// - Android: opens the APK in the system package installer (the user taps
///   Install; the APK must be signed with the same key as the installed app).
/// - Windows: runs the Inno Setup installer silently; it closes ZapDL,
///   upgrades in place and restarts it. A .zip is only revealed.
/// - macOS: opens the .dmg; the user drags ZapDL to Applications.
/// - Linux: reveals the tar.gz in the file manager.
class SystemInstaller implements UpdateInstaller {
  @override
  Future<InstallOutcome> install(String path, UpdatePlatform platform) async {
    switch (platform) {
      case UpdatePlatform.android:
        final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
        if (r.type != ResultType.done) throw StateError(r.message);
        return InstallOutcome.openedForUser;
      case UpdatePlatform.windows:
        if (path.toLowerCase().endsWith('.exe')) {
          await Process.start(
            path,
            const ['/SILENT', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
            mode: ProcessStartMode.detached,
            workingDirectory: p.dirname(path),
          );
          return InstallOutcome.launchedExit;
        }
        await revealInFileManager(path);
        return InstallOutcome.revealed;
      case UpdatePlatform.macos:
        await Process.run('open', [path]);
        return InstallOutcome.openedForUser;
      case UpdatePlatform.linux:
        await revealInFileManager(path);
        return InstallOutcome.revealed;
      case UpdatePlatform.ios:
        throw StateError('iOS updates come from the App Store or TestFlight');
    }
  }
}
