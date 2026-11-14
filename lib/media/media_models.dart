/// A single downloadable rendition of a piece of media.
class MediaFormat {
  const MediaFormat({
    required this.id,
    required this.url,
    required this.label,
    required this.extension,
    this.sizeBytes,
    this.hasVideo = true,
    this.hasAudio = true,
    this.isImage = false,
    this.headers = const {},
    this.note,
  });

  final String id;
  final String url;

  /// Short human label such as "720p mp4" or "Audio 128 kbps".
  final String label;
  final String extension;
  final int? sizeBytes;
  final bool hasVideo;
  final bool hasAudio;
  final bool isImage;
  final Map<String, String> headers;

  /// Honest caveat shown next to the format (e.g. "video only, no sound").
  final String? note;

  bool get isAudioOnly => hasAudio && !hasVideo && !isImage;
  bool get isVideoOnly => hasVideo && !hasAudio;
}

/// What an adapter found at a page URL.
class MediaInfo {
  const MediaInfo({
    required this.platform,
    required this.title,
    required this.sourcePage,
    required this.formats,
    this.uploader,
    this.thumbnail,
    this.duration,
  });

  final String platform;
  final String title;
  final String sourcePage;
  final String? uploader;
  final String? thumbnail;
  final Duration? duration;
  final List<MediaFormat> formats;

  /// The format selected by default: best muxed video, else best of anything.
  MediaFormat? get recommended {
    if (formats.isEmpty) return null;
    final muxed = formats.where((f) => f.hasVideo && f.hasAudio && !f.isImage);
    if (muxed.isNotEmpty) return muxed.first;
    return formats.first;
  }
}

/// Raised when a page has no downloadable media we can reach. [reason] is a
/// machine-readable code the UI maps to a localized message.
class MediaException implements Exception {
  const MediaException(this.reason, [this.detail]);

  /// One of: notFound, unsupported, loginRequired, network, blocked, parse.
  final String reason;
  final String? detail;

  @override
  String toString() => 'MediaException($reason${detail == null ? '' : ': $detail'})';
}
