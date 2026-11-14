import 'dart:async';
import 'dart:io';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'url_import.dart';

/// Receives text/links shared to ZapDL from other apps (the share sheet).
///
/// Android works through the intent filter that `dart tool/setup.dart` adds.
/// iOS needs a Share Extension target created in Xcode; see
/// docs/PLATFORM_NOTES.md. On other platforms this does nothing.
class ShareIntake {
  StreamSubscription<List<SharedMediaFile>>? _sub;

  static bool get supported => Platform.isAndroid || Platform.isIOS;

  Future<void> start(void Function(List<String> urls) onUrls) async {
    if (!supported) return;
    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      _deliver(initial, onUrls);
      await ReceiveSharingIntent.instance.reset();
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
            (files) => _deliver(files, onUrls),
            onError: (Object _) {},
          );
    } catch (_) {
      // Plugin not available: sharing simply does nothing.
    }
  }

  static void _deliver(List<SharedMediaFile> files, void Function(List<String>) onUrls) {
    final urls = <String>[];
    for (final f in files) {
      // For text and link shares the shared text is in `path`.
      if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
        urls.addAll(extractUrls(f.path));
      }
    }
    if (urls.isNotEmpty) onUrls(urls.toSet().toList());
  }

  Future<void> dispose() async => _sub?.cancel();
}
