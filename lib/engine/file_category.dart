import 'package:path/path.dart' as p;

enum FileCategory { video, audio, image, document, archive, application, other }

const _video = {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp', 'ts'};
const _audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus', 'aiff'};
const _image = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff', 'heic', 'ico', 'avif'};
const _document = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'ods',
  'odp', 'csv', 'epub', 'md', 'json', 'xml', 'html',
};
const _archive = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'tgz', 'zst', 'iso'};
const _application = {
  'exe', 'msi', 'apk', 'aab', 'dmg', 'pkg', 'deb', 'rpm', 'appimage', 'ipa', 'bat', 'sh',
};

/// Detects a category from the file extension first (most reliable for
/// downloads), then falls back to the MIME type.
FileCategory categoryFor(String fileName, {String? mime}) {
  final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  if (_video.contains(ext)) return FileCategory.video;
  if (_audio.contains(ext)) return FileCategory.audio;
  if (_image.contains(ext)) return FileCategory.image;
  if (_document.contains(ext)) return FileCategory.document;
  if (_archive.contains(ext)) return FileCategory.archive;
  if (_application.contains(ext)) return FileCategory.application;

  final m = (mime ?? '').toLowerCase();
  if (m.startsWith('video/')) return FileCategory.video;
  if (m.startsWith('audio/')) return FileCategory.audio;
  if (m.startsWith('image/')) return FileCategory.image;
  if (m.startsWith('text/') || m == 'application/pdf') return FileCategory.document;
  if (m.contains('zip') || m.contains('tar') || m.contains('compressed') || m.contains('7z')) {
    return FileCategory.archive;
  }
  if (m == 'application/vnd.android.package-archive' ||
      m == 'application/x-msdownload' ||
      m == 'application/x-msi') {
    return FileCategory.application;
  }
  return FileCategory.other;
}
