import 'package:path/path.dart' as p;

enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

/// Machine-readable error codes. The UI maps these to localized messages so
/// the engine never contains user-facing text.
enum DownloadErrorCode {
  network,
  timeout,
  http,
  notFound,
  accessDenied,
  rangeIgnored,
  changed,
  storageFull,
  permission,
  write,
  incomplete,
  invalidUrl,
  unsupportedScheme,
  tls,
  invalidHeader,
  proxy,
  unknown,
}

/// How HTTP connections reach the network.
enum ProxyMode {
  /// Use the system/environment proxy variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY).
  system,

  /// Always connect directly.
  none,

  /// Use [ProxyConfig.host] and [ProxyConfig.port]. HTTP proxies only (CONNECT
  /// is used for HTTPS targets); SOCKS is not supported by dart:io.
  manual,
}

class ProxyConfig {
  const ProxyConfig({
    this.mode = ProxyMode.system,
    this.host = '',
    this.port = 0,
    this.username,
    this.password,
  });

  final ProxyMode mode;
  final String host;
  final int port;
  final String? username;
  final String? password;

  bool get isManualValid =>
      host.isNotEmpty &&
      port > 0 &&
      port < 65536 &&
      !host.contains(RegExp(r'[\s@/:]')) &&
      !(username ?? '').contains(RegExp(r'[@:/]')) &&
      !(password ?? '').contains(RegExp(r'[@/]'));
}

/// A daily time-of-day window during which downloads may run.
/// A window with start > end spans midnight (for example 23:00-06:00).
class DailyWindow {
  const DailyWindow({required this.startMinute, required this.endMinute});

  /// Minutes after midnight, 0-1439.
  final int startMinute;
  final int endMinute;

  bool contains(DateTime t) {
    final m = t.hour * 60 + t.minute;
    if (startMinute == endMinute) return true;
    return startMinute < endMinute
        ? (m >= startMinute && m < endMinute)
        : (m >= startMinute || m < endMinute);
  }
}

/// One byte-range of a download, stored in its own part file.
/// [end] is inclusive; -1 means the total length is unknown.
class Segment {
  Segment({required this.start, required this.end, this.received = 0});

  final int start;
  int end;
  int received;

  int get length => end >= 0 ? end - start + 1 : -1;
  bool get isDone => end >= 0 && received >= length;

  Segment copy() => Segment(start: start, end: end, received: received);

  Map<String, dynamic> toJson() => {'s': start, 'e': end, 'r': received};

  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        start: (j['s'] as num).toInt(),
        end: (j['e'] as num).toInt(),
        received: (j['r'] as num? ?? 0).toInt(),
      );
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.directory,
    this.totalBytes = -1,
    this.receivedBytes = 0,
    this.status = DownloadStatus.queued,
    this.errorCode,
    this.errorDetail,
    this.needsRestart = false,
    this.etag,
    this.lastModified,
    this.mimeType,
    this.rangeSupported = false,
    this.connections = 1,
    this.priority = 0,
    DateTime? createdAt,
    this.completedAt,
    List<Segment>? segments,
    this.speedBps = 0,
    Map<String, String>? headers,
    Map<String, String>? secretHeaders,
    this.scheduledAt,
    this.sourcePage,
    this.groupId,
    this.groupOrder = 0,
    this.autoNext = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        segments = segments ?? <Segment>[],
        headers = headers ?? <String, String>{},
        secretHeaders = secretHeaders ?? <String, String>{};

  final String id;
  final String url;
  String fileName;
  final String directory;
  int totalBytes;
  int receivedBytes;
  DownloadStatus status;
  DownloadErrorCode? errorCode;
  String? errorDetail;

  /// True when the partial data can no longer be trusted (remote file changed,
  /// resume unsupported); retry then starts from scratch.
  bool needsRestart;
  String? etag;
  String? lastModified;
  String? mimeType;
  bool rangeSupported;
  int connections;
  int priority;
  final DateTime createdAt;
  DateTime? completedAt;
  final List<Segment> segments;

  /// Extra request headers that are safe to store (Referer, User-Agent, ...).
  final Map<String, String> headers;

  /// Credentials (Cookie, Authorization). Never written to the JSON store;
  /// kept in a [SecretStore] (secure storage in the app).
  final Map<String, String> secretHeaders;

  /// Do not start before this time (scheduled download).
  DateTime? scheduledAt;

  /// Page the media was extracted from (e.g. a YouTube watch URL), if any.
  String? sourcePage;

  /// Downloads in the same group run one after another in [groupOrder].
  String? groupId;
  int groupOrder;

  /// When this download completes, look for the next part (part1 -> part2)
  /// and add it automatically.
  bool autoNext;

  /// Transient: the finished file no longer exists on disk.
  bool fileMissing = false;

  /// Transient, not persisted.
  double speedBps;

  String get finalPath => p.join(directory, fileName);

  double? get progress {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  int? get etaSeconds {
    if (status != DownloadStatus.downloading || speedBps < 1 || totalBytes <= 0) {
      return null;
    }
    return ((totalBytes - receivedBytes) / speedBps).ceil();
  }

  bool get isFinished =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.canceled;

  DownloadTask copy() => DownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        directory: directory,
        totalBytes: totalBytes,
        receivedBytes: receivedBytes,
        status: status,
        errorCode: errorCode,
        errorDetail: errorDetail,
        needsRestart: needsRestart,
        etag: etag,
        lastModified: lastModified,
        mimeType: mimeType,
        rangeSupported: rangeSupported,
        connections: connections,
        priority: priority,
        createdAt: createdAt,
        completedAt: completedAt,
        segments: segments.map((s) => s.copy()).toList(),
        speedBps: speedBps,
        headers: Map.of(headers),
        secretHeaders: Map.of(secretHeaders),
        scheduledAt: scheduledAt,
        sourcePage: sourcePage,
        groupId: groupId,
        groupOrder: groupOrder,
        autoNext: autoNext,
      )..fileMissing = fileMissing;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'directory': directory,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'status': status.name,
        'errorCode': errorCode?.name,
        'errorDetail': errorDetail,
        'needsRestart': needsRestart,
        'etag': etag,
        'lastModified': lastModified,
        'mimeType': mimeType,
        'rangeSupported': rangeSupported,
        'connections': connections,
        'priority': priority,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'segments': segments.map((s) => s.toJson()).toList(),
        'headers': headers,
        'scheduledAt': scheduledAt?.toIso8601String(),
        'sourcePage': sourcePage,
        'groupId': groupId,
        'groupOrder': groupOrder,
        'autoNext': autoNext,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) {
    DownloadStatus status = DownloadStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => DownloadStatus.paused,
    );
    DownloadErrorCode? code;
    for (final c in DownloadErrorCode.values) {
      if (c.name == j['errorCode']) code = c;
    }
    return DownloadTask(
      id: j['id'] as String,
      url: j['url'] as String,
      fileName: j['fileName'] as String,
      directory: j['directory'] as String,
      totalBytes: (j['totalBytes'] as num? ?? -1).toInt(),
      receivedBytes: (j['receivedBytes'] as num? ?? 0).toInt(),
      status: status,
      errorCode: code,
      errorDetail: j['errorDetail'] as String?,
      needsRestart: j['needsRestart'] as bool? ?? false,
      etag: j['etag'] as String?,
      lastModified: j['lastModified'] as String?,
      mimeType: j['mimeType'] as String?,
      rangeSupported: j['rangeSupported'] as bool? ?? false,
      connections: (j['connections'] as num? ?? 1).toInt(),
      priority: (j['priority'] as num? ?? 0).toInt(),
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
      segments: [
        for (final s in (j['segments'] as List? ?? const []))
          Segment.fromJson((s as Map).cast<String, dynamic>()),
      ],
      headers: {
        for (final e in ((j['headers'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      },
      scheduledAt: DateTime.tryParse(j['scheduledAt'] as String? ?? ''),
      sourcePage: j['sourcePage'] as String?,
      groupId: j['groupId'] as String?,
      groupOrder: (j['groupOrder'] as num? ?? 0).toInt(),
      autoNext: j['autoNext'] as bool? ?? false,
    );
  }
}

/// Tunable engine behavior. Mutated live by the settings layer.
class EngineConfig {
  EngineConfig({
    this.maxConcurrent = 3,
    this.connections = 4,
    this.speedLimitBps = 0,
    this.maxRetries = 3,
    this.minSegmentBytes = 1024 * 1024,
    this.readTimeout = const Duration(seconds: 30),
    this.connectTimeout = const Duration(seconds: 20),
    this.retryBackoffUnit = const Duration(seconds: 2),
    this.proxy = const ProxyConfig(),
    this.allowedWindow,
  });

  /// Applied to every connection (probing and transfers).
  ProxyConfig proxy;

  /// When set, downloads only run inside this daily window; outside it,
  /// running downloads are stopped (kept as queued) and resume automatically.
  DailyWindow? allowedWindow;

  int maxConcurrent;
  int connections;

  /// Per-download limit in bytes per second; 0 = unlimited.
  int speedLimitBps;
  int maxRetries;
  int minSegmentBytes;
  Duration readTimeout;
  Duration connectTimeout;
  Duration retryBackoffUnit;
}
