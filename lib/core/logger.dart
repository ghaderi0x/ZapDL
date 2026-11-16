import 'package:flutter/foundation.dart';

/// Ordered so a level shows everything at or below its own index.
enum LogLevel { off, error, info, debug }

/// Minimal leveled logger. Output goes to the debug console only; nothing is
/// written to disk or sent anywhere.
///
/// Never log full URLs, headers or file contents: URLs can carry access
/// tokens. Use [redactUrl] when a URL must be mentioned.
class AppLogger {
  AppLogger({LogLevel? level}) : level = level ?? (kDebugMode ? LogLevel.debug : LogLevel.error);

  LogLevel level;

  void error(String message) => _emit(LogLevel.error, message);
  void info(String message) => _emit(LogLevel.info, message);
  void debug(String message) => _emit(LogLevel.debug, message);

  void _emit(LogLevel l, String message) {
    if (l.index > level.index) return;
    debugPrint('[ZapDL/${l.name}] $message');
  }
}

/// Reduces a URL to scheme and host, dropping credentials, path, query and
/// fragment, which may hold secrets.
String redactUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.hasScheme || u.host.isEmpty) return '<invalid-url>';
  return '${u.scheme}://${u.host}';
}
