import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Picks a default download directory per platform.
///
/// Desktop: the user's Downloads folder. Android: the app-specific external
/// directory (no storage permission needed; files are visible under
/// Android/data via file managers and to this app). iOS: the app Documents
/// folder (sandboxed).
Future<String> defaultDownloadDirectory() async {
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads.path;
  } catch (_) {}
  if (Platform.isAndroid) {
    final ext = await getExternalStorageDirectory();
    if (ext != null) return p.join(ext.path, 'Download');
  }
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'Downloads');
}

/// Reveals a file in the system file manager. Desktop only; mobile platforms
/// have no reliable equivalent, so callers hide the action there.
Future<void> revealInFileManager(String filePath) async {
  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,$filePath']);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', filePath]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [p.dirname(filePath)]);
  }
}
