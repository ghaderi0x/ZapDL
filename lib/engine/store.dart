import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract class DownloadStore {
  Future<List<DownloadTask>> load();
  Future<void> save(List<DownloadTask> tasks);
}

/// Persists download records as versioned JSON with atomic replace
/// (write temp file, then rename) so a crash never leaves a half-written file.
///
/// The [DownloadStore] interface lets this be swapped for a SQLite/Drift
/// implementation later without touching the engine.
class JsonFileDownloadStore implements DownloadStore {
  JsonFileDownloadStore(this.file);

  final File file;
  static const _version = 1;

  @override
  Future<List<DownloadTask>> load() async {
    try {
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      final list = (decoded as Map<String, dynamic>)['tasks'] as List;
      return [
        for (final item in list)
          DownloadTask.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      // Corrupt file: keep a copy for diagnosis instead of losing it silently.
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
      return [];
    }
  }

  @override
  Future<void> save(List<DownloadTask> tasks) {
    // Serialize writes: concurrent saves would share the temp file and the
    // second rename would fail.
    final json = jsonEncode({
      'version': _version,
      'tasks': tasks.map((t) => t.toJson()).toList(),
    });
    final next = _lastSave.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
    });
    _lastSave = next;
    return next;
  }

  Future<void> _lastSave = Future<void>.value();
}

class InMemoryDownloadStore implements DownloadStore {
  List<DownloadTask> saved = [];

  @override
  Future<List<DownloadTask>> load() async => saved.map((t) => t.copy()).toList();

  @override
  Future<void> save(List<DownloadTask> tasks) async {
    saved = tasks.map((t) => t.copy()).toList();
  }
}
