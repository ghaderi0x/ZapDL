import 'dart:async';

/// Links arriving from outside the app UI: the Android share sheet and files
/// dropped on the window. The shell listens and offers to add them.
class IncomingLinks {
  final _c = StreamController<List<String>>.broadcast();

  Stream<List<String>> get stream => _c.stream;

  void add(List<String> urls) {
    if (urls.isNotEmpty && !_c.isClosed) _c.add(urls);
  }

  Future<void> dispose() => _c.close();
}
