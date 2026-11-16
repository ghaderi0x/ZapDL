import 'release.dart';
import 'semver.dart';

enum UpdatePlatform { android, ios, windows, linux, macos }

/// Release files must follow this naming (see .github/workflows/release.yml):
///
///   ZapDL-<version>-android.apk            universal APK
///   ZapDL-<version>-windows-x64-setup.exe  installer (preferred on Windows)
///   ZapDL-<version>-windows-x64.zip        portable
///   ZapDL-<version>-linux-x64.tar.gz
///   ZapDL-<version>-macos.dmg
///   SHA256SUMS.txt                         checksums of all of the above
///
/// iOS cannot be updated outside the App Store/TestFlight, so it has no asset.
String? checksumAssetName(List<ReleaseAsset> assets) {
  for (final a in assets) {
    if (a.name.toLowerCase() == 'sha256sums.txt') return a.name;
  }
  return null;
}

/// Architecture token used in file names: "x64" or "arm64".
String archToken(String dartPlatformVersion) {
  final m = RegExp(r'on "[a-z]+_([a-z0-9]+)"').firstMatch(dartPlatformVersion);
  final arch = m?.group(1) ?? 'x64';
  return (arch == 'arm64' || arch == 'arm64e') ? 'arm64' : 'x64';
}

/// The best asset for this platform, or null when there is none.
ReleaseAsset? selectAsset(
  List<ReleaseAsset> assets, {
  required UpdatePlatform platform,
  required String arch,
}) {
  bool has(ReleaseAsset a, String ext) => a.name.toLowerCase().endsWith(ext);
  bool tagged(ReleaseAsset a, String token) =>
      a.name.toLowerCase().contains('-$token');

  List<ReleaseAsset> pick(String os, List<String> exts, {bool archSpecific = true}) {
    final out = <ReleaseAsset>[];
    for (final ext in exts) {
      for (final a in assets) {
        if (!tagged(a, os) || !has(a, ext)) continue;
        if (archSpecific && !a.name.toLowerCase().contains('-$arch')) continue;
        out.add(a);
      }
    }
    return out;
  }

  switch (platform) {
    case UpdatePlatform.android:
      // Only the GitHub APK (`-android.apk`). The `-android-store.apk` build
      // is for app stores and has its updater disabled.
      final r = assets.where((a) => a.name.toLowerCase().endsWith('-android.apk')).toList();
      return r.isEmpty ? null : r.first;
    case UpdatePlatform.windows:
      final r = pick('windows', ['-setup.exe', '.zip']);
      return r.isEmpty ? null : r.first;
    case UpdatePlatform.linux:
      final r = pick('linux', ['.tar.gz']);
      return r.isEmpty ? null : r.first;
    case UpdatePlatform.macos:
      final r = pick('macos', ['.dmg', '.zip'], archSpecific: false);
      return r.isEmpty ? null : r.first;
    case UpdatePlatform.ios:
      return null;
  }
}

/// Extracts the version from a release file name such as
/// `ZapDL-1.2.0-windows-x64-setup.exe`; null if there is none.
SemVer? versionFromFileName(String fileName) {
  final m = RegExp(r'-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+?)?)(?=-(?:android|windows|linux|macos|ios)|\.(?:apk|exe|zip|dmg|gz|tar)\b)')
      .firstMatch(fileName);
  return m == null ? null : SemVer.tryParse(m.group(1)!);
}

/// File extensions that can be installed on [platform].
bool isInstallableFile(String fileName, UpdatePlatform platform) {
  final n = fileName.toLowerCase();
  return switch (platform) {
    UpdatePlatform.android => n.endsWith('.apk'),
    UpdatePlatform.windows => n.endsWith('.exe') || n.endsWith('.zip'),
    UpdatePlatform.linux => n.endsWith('.tar.gz') || n.endsWith('.appimage'),
    UpdatePlatform.macos => n.endsWith('.dmg') || n.endsWith('.zip'),
    UpdatePlatform.ios => false,
  };
}
