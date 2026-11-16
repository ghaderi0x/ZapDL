import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

bool get isMobilePlatform => Platform.isAndroid || Platform.isIOS;
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Name of the folder (inside the system Downloads folder) where ZapDL saves.
const zapFilesFolder = 'ZapFiles';

/// Default save location: `<Downloads>/ZapFiles`.
///
/// Desktop: the user's Downloads folder. Android: the public Download folder
/// when this app can write there, otherwise its app-specific external folder
/// (no permission needed). iOS: the app Documents folder (sandboxed).
Future<String> defaultDownloadDirectory() async {
  final dir = await _pickDefaultDirectory();
  try {
    await Directory(dir).create(recursive: true);
  } catch (_) {}
  return dir;
}

Future<String> _pickDefaultDirectory() async {
  if (Platform.isAndroid) {
    const shared = '/storage/emulated/0/Download';
    final target = p.join(shared, zapFilesFolder);
    if (await _canWrite(target)) return target;
    final ext = await getExternalStorageDirectory();
    if (ext != null) return p.join(ext.path, 'Download', zapFilesFolder);
  }
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return p.join(downloads.path, zapFilesFolder);
  } catch (_) {}
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, zapFilesFolder);
}

/// True when a file can really be created in [dir] (Android scoped storage may refuse).
Future<bool> _canWrite(String dir) async {
  try {
    await Directory(dir).create(recursive: true);
    final probe = File(p.join(dir, '.zapdl_write_test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
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
