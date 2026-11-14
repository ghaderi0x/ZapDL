// Sets the app version everywhere it must match, and prepares the changelog.
//
//   dart tool/bump_version.dart 0.2.0
//
// Updates pubspec.yaml, lib/core/app_info.dart and CHANGELOG.md, then prints
// the git commands to publish. Publishing = pushing a tag (see docs/GITHUB_GUIDE.md).
import 'dart:io';

void main(List<String> args) {
  if (args.length != 1 ||
      !RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$').hasMatch(args.first)) {
    stderr.writeln('Usage: dart tool/bump_version.dart <major.minor.patch[-prerelease]>');
    exit(64);
  }
  final v = args.first;

  final pubspec = File('pubspec.yaml');
  var p = pubspec.readAsStringSync();
  final m = RegExp(r'^version:\s*[\d.]+(?:-[0-9A-Za-z.]+)?(?:\+(\d+))?\s*$', multiLine: true)
      .firstMatch(p);
  if (m == null) {
    stderr.writeln('Could not find "version:" in pubspec.yaml');
    exit(1);
  }
  final build = (int.tryParse(m.group(1) ?? '0') ?? 0) + 1;
  p = p.replaceFirst(m.group(0)!, 'version: $v+$build');
  pubspec.writeAsStringSync(p);

  final info = File('lib/core/app_info.dart');
  info.writeAsStringSync(info
      .readAsStringSync()
      .replaceFirst(RegExp(r"const appVersion = '[^']*';"), "const appVersion = '$v';"));

  final log = File('CHANGELOG.md');
  var c = log.readAsStringSync();
  if (c.contains('## [$v]')) {
    stderr.writeln('CHANGELOG.md already has a section for $v');
    exit(1);
  }
  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  c = c.replaceFirst('## [Unreleased]', '## [Unreleased]\n\n## [$v] - $date');
  log.writeAsStringSync(c);

  stdout.writeln('''
Version set to $v (build $build).
Now:
  1. Open CHANGELOG.md and make sure the [$v] section lists what changed.
  2. flutter test
  3. git add -A && git commit -m "Release $v"
  4. git tag v$v && git push && git push origin v$v
GitHub Actions then builds every platform and publishes the release.''');
}
