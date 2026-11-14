// One-time project setup. Run from the project root:
//
//     dart tool/setup.dart
//
// It generates the platform folders (android/, ios/, windows/, linux/, macos/)
// with `flutter create`, then patches in the permissions ZapDL needs:
//   - Android: permissions (network, foreground service, notifications, install
//              updates), the background-download foreground service (Kotlin),
//              the share-sheet intent filter and single-instance launch mode
//   - Linux:   nothing to patch (see docs/PLATFORM_NOTES.md for system packages)
//   - macOS:   sandbox entitlements for network access and the Downloads folder
//   - iOS:     file-sharing keys so downloaded files are visible in the Files app
// Finally it fetches packages and generates the localization classes.
//
// Platform folders for platforms your OS cannot build are still created; you
// simply cannot build them locally (e.g. iOS/macOS need a Mac).

import 'dart:io';

Future<int> run(String cmd, List<String> args) async {
  stdout.writeln('\$ $cmd ${args.join(' ')}');
  final p = await Process.start(cmd, args,
      mode: ProcessStartMode.inheritStdio, runInShell: true);
  return p.exitCode;
}

void patchFile(String path, String Function(String) patch) {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('  skip (not found): $path');
    return;
  }
  final before = f.readAsStringSync();
  final after = patch(before);
  if (after == before) {
    stdout.writeln('  unchanged: $path');
  } else {
    f.writeAsStringSync(after);
    stdout.writeln('  patched:   $path');
  }
}

const androidPermissions = [
  'android.permission.INTERNET',
  'android.permission.ACCESS_NETWORK_STATE',
  'android.permission.FOREGROUND_SERVICE',
  'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.REQUEST_INSTALL_PACKAGES',
  'android.permission.WAKE_LOCK',
];

/// Adds every permission ZapDL needs (idempotent).
String addAndroidPermissions(String xml) {
  var out = xml;
  for (final perm in androidPermissions) {
    if (out.contains(perm)) continue;
    out = out.replaceFirstMapped(
      RegExp(r'<manifest[^>]*>'),
      (m) => '${m[0]}\n    <uses-permission android:name="$perm"/>',
    );
  }
  return out;
}

/// Registers the download foreground service, the share-sheet intent filter
/// and single-instance launch mode (so a share opens the running app).
String patchAndroidApplication(String xml) {
  var out = xml;
  if (!out.contains('.DownloadService')) {
    out = out.replaceFirst(
      '</application>',
      '    <service\n'
      '        android:name=".DownloadService"\n'
      '        android:exported="false"\n'
      '        android:foregroundServiceType="dataSync"/>\n'
      '    </application>',
    );
  }
  if (!out.contains('android.intent.action.SEND')) {
    out = out.replaceFirst(
      '</activity>',
      '    <intent-filter>\n'
      '        <action android:name="android.intent.action.SEND"/>\n'
      '        <category android:name="android.intent.category.DEFAULT"/>\n'
      '        <data android:mimeType="text/plain"/>\n'
      '    </intent-filter>\n'
      '    </activity>',
    );
  }
  out = out.replaceFirst(
    RegExp(r'android:launchMode="[^"]*"'),
    'android:launchMode="singleTask"',
  );
  return out;
}

/// Copies the Kotlin service files into the app package and registers the
/// method channel in MainActivity.
void installAndroidService() {
  final root = Directory('android/app/src/main/kotlin');
  if (!root.existsSync()) {
    stdout.writeln('  skip (no android/ Kotlin folder)');
    return;
  }
  final main = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('MainActivity.kt'))
      .toList();
  if (main.isEmpty) {
    stdout.writeln('  skip (MainActivity.kt not found)');
    return;
  }
  final dir = main.first.parent.path;
  final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true)
          .firstMatch(main.first.readAsStringSync())
          ?.group(1) ??
      'com.uniqueone.zapdl';
  for (final name in ['DownloadService.kt', 'BackgroundChannel.kt']) {
    final src = File('tool/templates/android/$name').readAsStringSync();
    File('$dir/$name').writeAsStringSync(
      src.replaceFirst(RegExp(r'^package\s+[\w.]+', multiLine: true), 'package $pkg'),
    );
    stdout.writeln('  wrote:     $dir/$name');
  }
  patchFile(main.first.path, (kt) {
    if (kt.contains('BackgroundChannel')) return kt;
    return 'package $pkg\n\n'
        'import io.flutter.embedding.android.FlutterActivity\n'
        'import io.flutter.embedding.engine.FlutterEngine\n'
        'import io.flutter.plugin.common.MethodChannel\n\n'
        'class MainActivity : FlutterActivity() {\n'
        '    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {\n'
        '        super.configureFlutterEngine(flutterEngine)\n'
        '        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.zapdl/background")\n'
        '            .setMethodCallHandler(BackgroundChannel(applicationContext))\n'
        '    }\n'
        '}\n';
  });
}

/// Flutter's Linux template compiles every target with `-Werror`, which breaks
/// the build as soon as a plugin (tray_manager, flutter_secure_storage) triggers
/// a compiler deprecation warning on a newer clang/GCC. Keep warnings, drop the error.
String relaxLinuxWarnings(String cmake) =>
    cmake.replaceAll('-Wall -Werror', '-Wall -Wno-deprecated-declarations');

String addEntitlements(String plist) {
  const keys = [
    'com.apple.security.network.client',
    'com.apple.security.files.user-selected.read-write',
    'com.apple.security.files.downloads.read-write',
  ];
  var out = plist;
  for (final k in keys) {
    if (out.contains(k)) continue;
    out = out.replaceFirst('</dict>', '\t<key>$k</key>\n\t<true/>\n</dict>');
  }
  return out;
}

String addIosKeys(String plist) {
  var out = plist;
  const entries = {
    'UIFileSharingEnabled': '<true/>',
    'LSSupportsOpeningDocumentsInPlace': '<true/>',
  };
  entries.forEach((k, v) {
    if (out.contains(k)) return;
    out = out.replaceFirst('</dict>', '\t<key>$k</key>\n\t$v\n</dict>');
  });
  return out;
}

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the project root (the folder with pubspec.yaml).');
    exit(2);
  }

  // `flutter create` on an existing folder may rewrite these; keep our versions.
  final keep = <String, String>{
    for (final path in ['pubspec.yaml', 'lib/main.dart', 'analysis_options.yaml'])
      if (File(path).existsSync()) path: File(path).readAsStringSync(),
  };

  final create = await run('flutter', [
    'create',
    '--project-name=zapdl',
    '--org=com.uniqueone',
    '--platforms=android,ios,windows,linux,macos',
    '.',
  ]);
  if (create != 0) {
    stderr.writeln('flutter create failed. Is Flutter 3.27 or newer on your PATH?');
    exit(create);
  }

  keep.forEach((path, content) => File(path).writeAsStringSync(content));

  stdout.writeln('\nPatching platform permissions...');
  patchFile('android/app/src/main/AndroidManifest.xml',
      (x) => patchAndroidApplication(addAndroidPermissions(x)));
  installAndroidService();
  patchFile('linux/CMakeLists.txt', relaxLinuxWarnings);
  patchFile('macos/Runner/DebugProfile.entitlements', addEntitlements);
  patchFile('macos/Runner/Release.entitlements', addEntitlements);
  patchFile('ios/Runner/Info.plist', addIosKeys);

  // flutter create overwrites the template test and main; restore ours.
  final defaultTest = File('test/widget_test.dart');
  if (defaultTest.existsSync()) defaultTest.deleteSync();

  final pub = await run('flutter', ['pub', 'get']);
  if (pub != 0) exit(pub);
  final l10n = await run('flutter', ['gen-l10n']);
  if (l10n != 0) exit(l10n);
  stdout.writeln('\nGenerating launcher icons from assets/icon...');
  final icons = await run('dart', ['run', 'flutter_launcher_icons']);
  if (icons != 0) {
    stderr.writeln('Launcher icon generation failed; the default Flutter icons remain.');
  }

  stdout.writeln('''

Setup complete. Next:
  flutter analyze
  flutter test
  flutter run -d windows   # or linux / macos / <android device> / <ios simulator>
''');
}
