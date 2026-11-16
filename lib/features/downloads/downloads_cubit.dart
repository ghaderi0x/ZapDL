import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../engine/engine.dart';
import '../../engine/file_category.dart';
import '../../engine/models.dart';
import '../../engine/probe.dart';
import '../../media/media_models.dart';
import '../../media/resolver.dart';

enum StatusFilter { all, active, completed, failed }

class DownloadsState extends Equatable {
  const DownloadsState({
    this.tasks = const [],
    this.filter = StatusFilter.all,
    this.category,
    this.query = '',
    this.gate = EngineGate.open,
    this.revision = 0,
  });

  final List<DownloadTask> tasks;
  final StatusFilter filter;
  final FileCategory? category;
  final String query;

  /// Why nothing is transferring (offline, outside schedule, suspended), if so.
  final EngineGate gate;

  /// Bumped on every engine update so a progress tick is never mistaken for
  /// "no change" (the task objects are mutable snapshots).
  final int revision;

  DownloadsState copyWith({
    List<DownloadTask>? tasks,
    StatusFilter? filter,
    FileCategory? category,
    bool clearCategory = false,
    String? query,
    EngineGate? gate,
    int? revision,
  }) =>
      DownloadsState(
        tasks: tasks ?? this.tasks,
        filter: filter ?? this.filter,
        category: clearCategory ? null : (category ?? this.category),
        query: query ?? this.query,
        gate: gate ?? this.gate,
        revision: revision ?? this.revision,
      );

  static bool matchesStatus(StatusFilter f, DownloadTask t) {
    switch (f) {
      case StatusFilter.all:
        return true;
      case StatusFilter.active:
        return t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.paused;
      case StatusFilter.completed:
        return t.status == DownloadStatus.completed;
      case StatusFilter.failed:
        return t.status == DownloadStatus.failed || t.status == DownloadStatus.canceled;
    }
  }

  static FileCategory categoryOf(DownloadTask t) =>
      categoryFor(t.fileName, mime: t.mimeType);

  List<DownloadTask> get visible {
    final q = query.trim().toLowerCase();
    final list = tasks.where((t) {
      if (!matchesStatus(filter, t)) return false;
      if (category != null && categoryOf(t) != category) return false;
      if (q.isNotEmpty && !t.fileName.toLowerCase().contains(q) && !t.url.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  int countFor(StatusFilter f) => tasks.where((t) => matchesStatus(f, t)).length;
  int countForCategory(FileCategory? c) =>
      c == null ? tasks.length : tasks.where((t) => categoryOf(t) == c).length;

  int get activeCount => tasks.where((t) => t.status == DownloadStatus.downloading).length;
  double get totalSpeed => tasks.fold<double>(0, (a, t) => a + t.speedBps);

  @override
  List<Object?> get props => [tasks, filter, category, query, gate, revision];
}

class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit(this._engine, {MediaResolver? resolver})
      : _resolver = resolver,
        super(DownloadsState(tasks: _engine.snapshot, gate: _engine.gate)) {
    _sub = _engine.updates
        .listen((tasks) => emit(state.copyWith(tasks: tasks, revision: state.revision + 1)));
    _gateSub = _engine.gateUpdates.listen((g) => emit(state.copyWith(gate: g)));
  }

  final DownloadEngine _engine;
  final MediaResolver? _resolver;
  late final StreamSubscription<List<DownloadTask>> _sub;
  late final StreamSubscription<EngineGate> _gateSub;

  Future<ProbeResult> probe(
    String url, {
    Map<String, String> headers = const {},
    String? cookies,
  }) =>
      _engine.probe(url, headers: headers, cookies: cookies);

  /// Finds the media behind a web-page link (YouTube, Reddit, Telegram, ...).
  Future<MediaInfo> resolveMedia(String url) {
    final r = _resolver;
    if (r == null) throw const MediaException('unsupported');
    r.proxy = _engine.config.proxy;
    return r.resolve(url);
  }

  Future<void> add({
    required String url,
    required String directory,
    String? fileName,
    ProbeResult? probe,
    Map<String, String> headers = const {},
    String? cookies,
    DateTime? scheduledAt,
    String? sourcePage,
    bool autoNext = false,
  }) =>
      _engine.add(
        url: url,
        directory: directory,
        fileName: fileName,
        probe: probe,
        headers: headers,
        cookies: cookies,
        scheduledAt: scheduledAt,
        sourcePage: sourcePage,
        autoNext: autoNext,
      );

  /// Adds many links at once (drag-and-drop, share sheet, pasted lists).
  /// Duplicates are skipped. Returns how many were added and how many failed.
  Future<({int added, int failed})> addMany(List<String> urls, String directory) async {
    final fresh = urls.where((u) => !isDuplicate(u)).toSet().toList();
    var added = 0;
    var failed = 0;
    for (var i = 0; i < fresh.length; i += 4) {
      final batch = fresh.skip(i).take(4);
      await Future.wait(batch.map((u) async {
        try {
          await _engine.add(url: u, directory: directory);
          added++;
        } catch (_) {
          failed++;
        }
      }));
    }
    return (added: added, failed: failed);
  }

  /// Adds links as one group: they download one at a time, in the given order.
  /// Links are probed in order so the order is kept. [autoNext] makes the last
  /// part look for its successor (part2, part3, ...) when it finishes.
  Future<({int added, int failed})> addGroup(
    List<String> urls,
    String directory, {
    bool autoNext = false,
  }) async {
    final list = <String>[];
    for (final u in urls) {
      final t = u.trim();
      if (t.isNotEmpty && !list.contains(t) && !isDuplicate(t)) list.add(t);
    }
    final groupId = 'g${DateTime.now().microsecondsSinceEpoch}';
    var added = 0;
    var failed = 0;
    for (var i = 0; i < list.length; i++) {
      try {
        await _engine.add(
          url: list[i],
          directory: directory,
          groupId: groupId,
          groupOrder: i,
          autoNext: autoNext && i == list.length - 1,
        );
        added++;
      } catch (_) {
        failed++;
      }
    }
    return (added: added, failed: failed);
  }

  /// Downloads a finished-but-deleted file again from its original link.
  Future<void> redownload(DownloadTask t) async {
    await _engine.add(
      url: t.url,
      directory: t.directory,
      fileName: t.fileName,
      headers: t.headers,
    );
    await _engine.remove(t.id);
  }

  /// Re-checks which finished files still exist (call when the app is focused).
  void refreshFiles() => _engine.refreshMissingFiles();

  void schedule(String id, DateTime? at) => _engine.schedule(id, at);

  bool isDuplicate(String url) {
    final u = url.trim();
    return state.tasks.any((t) => t.url == u);
  }

  void pause(String id) => _engine.pause(id);
  Future<void> resume(String id) => _engine.resume(id);
  Future<void> cancel(String id) => _engine.cancel(id);
  Future<void> remove(String id, {bool deleteFile = false}) =>
      _engine.remove(id, deleteFile: deleteFile);
  Future<int> cleanTempFiles() => _engine.cleanOrphanedParts();
  void pauseAll() => _engine.pauseAll();
  Future<void> resumeAll() => _engine.resumeAll();

  void setFilter(StatusFilter f) => emit(state.copyWith(filter: f));
  void setCategory(FileCategory? c) =>
      emit(c == null ? state.copyWith(clearCategory: true) : state.copyWith(category: c));
  void setQuery(String q) => emit(state.copyWith(query: q));

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _gateSub.cancel();
    return super.close();
  }
}
