import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapdl/update/asset_selector.dart';
import 'package:zapdl/update/release.dart';
import 'package:zapdl/update/semver.dart';
import 'package:zapdl/update/update_cubit.dart';
import 'package:zapdl/update/update_service.dart';

class FakeInstaller implements UpdateInstaller {
  String? installed;
  @override
  Future<InstallOutcome> install(String path, UpdatePlatform platform) async {
    installed = path;
    return InstallOutcome.openedForUser;
  }
}

/// Pretends to be api.github.com plus the asset CDN.
class FakeGitHub {
  FakeGitHub(this.assetBytes);

  final Uint8List assetBytes;
  String latestTag = 'v1.1.0';
  bool prerelease = false;
  bool rateLimited = false;
  bool includeSums = true;
  bool corruptSums = false;
  int apiHits = 0;
  int notModified = 0;
  late HttpServer _s;
  String get base => 'http://127.0.0.1:${_s.port}';
  static const etag = '"abc"';

  Map<String, dynamic> release(String tag, {bool pre = false}) {
    final v = tag.replaceFirst('v', '');
    return {
      'tag_name': tag,
      'name': 'ZapDL $v',
      'body': 'Notes for $v',
      'html_url': 'https://github.com/ghaderi0x/ZapDL/releases/tag/$tag',
      'prerelease': pre,
      'draft': false,
      'published_at': '2026-01-01T00:00:00Z',
      'assets': [
        {
          'name': 'ZapDL-$v-android.apk',
          'browser_download_url': '$base/dl/ZapDL-$v-android.apk',
          'size': assetBytes.length,
        },
        if (includeSums)
          {
            'name': 'SHA256SUMS.txt',
            'browser_download_url': '$base/dl/SHA256SUMS.txt',
            'size': 100,
          },
      ],
    };
  }

  Future<void> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((req) async {
      final res = req.response;
      final path = req.uri.path;
      if (path.endsWith('/releases/latest')) {
        apiHits++;
        if (rateLimited) {
          res.statusCode = 403;
        } else if (req.headers.value('if-none-match') == etag) {
          notModified++;
          res.statusCode = 304;
        } else {
          res.headers.set('etag', etag);
          res.headers.contentType = ContentType.json;
          res.write(jsonEncode(release(latestTag, pre: prerelease)));
        }
      } else if (path.endsWith('/releases')) {
        apiHits++;
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode([release('v1.2.0-beta.1', pre: true), release('v1.1.0')]));
      } else if (path.endsWith('SHA256SUMS.txt')) {
        final hex = corruptSums ? '0' * 64 : sha256.convert(assetBytes).toString();
        final v = latestTag.replaceFirst('v', '');
        res.write('$hex  ZapDL-$v-android.apk\n');
      } else if (path.endsWith('.apk')) {
        res.headers.contentType = ContentType.binary;
        res.contentLength = assetBytes.length;
        res.add(assetBytes);
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }

  Future<void> stop() => _s.close(force: true);
}

void main() {
  group('SemVer', () {
    test('parses and orders versions, pre-releases and v-prefix', () {
      SemVer v(String s) => SemVer.tryParse(s)!;
      expect(v('v1.2.3'), v('1.2.3'));
      expect(v('1.10.0') > v('1.9.9'), isTrue);
      expect(v('1.0.0') > v('1.0.0-rc.1'), isTrue);
      expect(v('1.0.0-rc.2') > v('1.0.0-rc.1'), isTrue);
      expect(v('1.0.0-rc.10') > v('1.0.0-rc.2'), isTrue);
      expect(v('1.0.0-alpha') < v('1.0.0-beta'), isTrue);
      expect(v('1.0.0-1') < v('1.0.0-alpha'), isTrue);
      expect(v('1.0.0+5'), v('1.0.0'), reason: 'build metadata is ignored');
      expect(SemVer.tryParse('latest'), isNull);
      expect(SemVer.tryParse('1.2'), isNull);
    });
  });

  group('release parsing', () {
    test('ignores drafts and non-semver tags; honors the prerelease choice', () {
      final body = jsonEncode([
        {'tag_name': 'nightly', 'assets': []},
        {'tag_name': 'v9.9.9', 'draft': true, 'assets': []},
        {'tag_name': 'v1.2.0-beta.1', 'prerelease': true, 'assets': []},
        {'tag_name': 'v1.1.0', 'assets': []},
      ]);
      expect(ReleaseInfo.parse(body, includePrereleases: false)!.tag, 'v1.1.0');
      expect(ReleaseInfo.parse(body, includePrereleases: true)!.tag, 'v1.2.0-beta.1');
      expect(ReleaseInfo.parse('not json', includePrereleases: false), isNull);
    });

    test('reads GitHub digests and checksum files', () {
      final r = ReleaseInfo.fromJson({
        'tag_name': 'v1.0.0',
        'assets': [
          {
            'name': 'a.apk',
            'browser_download_url': 'https://x/a.apk',
            'size': 5,
            'digest': 'sha256:${'AB' * 32}',
          }
        ],
      })!;
      expect(r.assets.single.sha256, 'ab' * 32);
      final sums = parseChecksumFile('${'a' * 64}  one.zip\n${'b' * 64} *two.exe\njunk');
      expect(sums, {'one.zip': 'a' * 64, 'two.exe': 'b' * 64});
    });
  });

  group('asset selection', () {
    ReleaseAsset a(String n) => ReleaseAsset(name: n, url: 'https://x/$n', size: 1);
    final all = [
      a('ZapDL-1.0.0-android-store.apk'),
      a('ZapDL-1.0.0-android.apk'),
      a('ZapDL-1.0.0-windows-x64.zip'),
      a('ZapDL-1.0.0-windows-x64-setup.exe'),
      a('ZapDL-1.0.0-windows-arm64-setup.exe'),
      a('ZapDL-1.0.0-linux-x64.tar.gz'),
      a('ZapDL-1.0.0-macos.dmg'),
      a('SHA256SUMS.txt'),
    ];

    test('chooses the right file per platform and architecture', () {
      String? pick(UpdatePlatform p, [String arch = 'x64']) =>
          selectAsset(all, platform: p, arch: arch)?.name;
      expect(pick(UpdatePlatform.android), 'ZapDL-1.0.0-android.apk',
          reason: 'the store build must never be offered as an update');
      expect(pick(UpdatePlatform.windows), 'ZapDL-1.0.0-windows-x64-setup.exe');
      expect(pick(UpdatePlatform.windows, 'arm64'), 'ZapDL-1.0.0-windows-arm64-setup.exe');
      expect(pick(UpdatePlatform.linux), 'ZapDL-1.0.0-linux-x64.tar.gz');
      expect(pick(UpdatePlatform.linux, 'arm64'), isNull);
      expect(pick(UpdatePlatform.macos), 'ZapDL-1.0.0-macos.dmg');
      expect(pick(UpdatePlatform.ios), isNull);
    });

    test('architecture token from Platform.version', () {
      expect(archToken('3.6.0 (stable) on "windows_x64"'), 'x64');
      expect(archToken('3.6.0 (stable) on "linux_arm64"'), 'arm64');
      expect(archToken('weird'), 'x64');
    });

    test('version from file name and installable types', () {
      expect(versionFromFileName('ZapDL-1.2.3-windows-x64-setup.exe'), const SemVer(1, 2, 3));
      expect(versionFromFileName('ZapDL-1.2.3-beta.1-android.apk').toString(), '1.2.3-beta.1');
      expect(versionFromFileName('ZapDL-1.2.3.dmg'), const SemVer(1, 2, 3));
      expect(versionFromFileName('random.apk'), isNull);
      expect(isInstallableFile('x.apk', UpdatePlatform.android), isTrue);
      expect(isInstallableFile('x.apk', UpdatePlatform.windows), isFalse);
      expect(isInstallableFile('x.AppImage', UpdatePlatform.linux), isTrue);
    });
  });

  group('UpdateService against a fake GitHub', () {
    late Directory tmp;
    late FakeGitHub gh;
    late Uint8List apk;
    late SharedPreferences prefs;
    late FakeInstaller installer;
    DateTime now = DateTime(2026, 6, 1);

    UpdateService make({String current = '1.0.0'}) => UpdateService(
          prefs: prefs,
          currentVersion: SemVer.tryParse(current)!,
          updatesDir: p.join(tmp.path, 'updates'),
          platform: UpdatePlatform.android,
          arch: 'x64',
          installer: installer,
          apiBase: gh.base,
          clock: () => now,
        );

    setUpAll(() => HttpOverrides.global = null);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tmp = await Directory.systemTemp.createTemp('zapdl_upd');
      apk = Uint8List.fromList(List.generate(300 * 1024, (i) => i & 0xFF));
      gh = FakeGitHub(apk);
      await gh.start();
      installer = FakeInstaller();
      now = DateTime(2026, 6, 1);
    });

    tearDown(() async {
      await gh.stop();
      await tmp.delete(recursive: true);
    });

    test('finds a newer release, and reports up-to-date for the same version', () async {
      final s = make();
      final r = await s.check(force: true);
      expect(r.newer, isTrue);
      expect(r.release!.version, const SemVer(1, 1, 0));
      expect(s.assetFor(r.release!)!.name, 'ZapDL-1.1.0-android.apk');
      final same = await make(current: '1.1.0').check(force: true);
      expect(same.newer, isFalse);
      final ahead = await make(current: '2.0.0').check(force: true);
      expect(ahead.newer, isFalse);
    });

    test('uses ETag (304) and a fresh cache to spare the API', () async {
      final s = make();
      await s.check(force: true);
      expect(gh.apiHits, 1);
      now = now.add(const Duration(minutes: 5));
      final cached = await s.check(); // fresh cache: no request at all
      expect(cached.fromCache, isTrue);
      expect(gh.apiHits, 1);
      now = now.add(const Duration(hours: 2));
      final again = await s.check(force: true); // conditional request
      expect(gh.apiHits, 2);
      expect(gh.notModified, 1);
      expect(again.release!.tag, 'v1.1.0');
    });

    test('rate limiting is reported, not treated as "no update"', () async {
      gh.rateLimited = true;
      await expectLater(
        make().check(force: true),
        throwsA(isA<UpdateException>().having((e) => e.code, 'code', 'rateLimited')),
      );
    });

    test('prerelease channel picks the newest including betas', () async {
      final r = await make().check(includePrereleases: true, force: true);
      expect(r.release!.tag, 'v1.2.0-beta.1');
    });

    test('auto-check is due at most once per 24h and can be turned off', () async {
      final s = make();
      expect(s.autoCheckDue(enabled: true), isTrue);
      expect(s.autoCheckDue(enabled: false), isFalse);
      await s.check(force: true);
      expect(s.autoCheckDue(enabled: true), isFalse);
      now = now.add(const Duration(hours: 25));
      expect(s.autoCheckDue(enabled: true), isTrue);
    });

    test('downloads, verifies against SHA256SUMS and installs', () async {
      final s = make();
      addTearDown(s.dispose);
      final r = (await s.check(force: true)).release!;
      final progress = <int>[];
      final got = await s.download(r, s.assetFor(r)!, onProgress: (a, t, _) => progress.add(a));
      expect(got.verified, isTrue);
      expect(await got.file.readAsBytes(), apk);
      expect(progress, isNotEmpty);
      final outcome = await s.install(got.file);
      expect(outcome, InstallOutcome.openedForUser);
      expect(installer.installed, got.file.path);
    });

    test('a corrupted download is rejected and deleted', () async {
      gh.corruptSums = true;
      final s = make();
      addTearDown(s.dispose);
      final r = (await s.check(force: true)).release!;
      await expectLater(
        s.download(r, s.assetFor(r)!),
        throwsA(isA<UpdateException>().having((e) => e.code, 'code', 'checksum')),
      );
      final left = Directory(p.join(tmp.path, 'updates'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.apk'));
      expect(left, isEmpty);
    });

    test('a release without checksums downloads but is marked unverified', () async {
      gh.includeSums = false;
      final s = make();
      addTearDown(s.dispose);
      final r = (await s.check(force: true)).release!;
      final got = await s.download(r, s.assetFor(r)!);
      expect(got.verified, isFalse);
    });

    test('cubit: check -> download -> ready -> install', () async {
      final cubit = UpdateCubit(make());
      addTearDown(cubit.close);
      final newer = await cubit.check();
      expect(newer!.tag, 'v1.1.0');
      expect(cubit.state.phase, UpdatePhase.available);
      await cubit.download();
      expect(cubit.state.phase, UpdatePhase.ready);
      expect(cubit.state.verified, isTrue);
      expect(await cubit.install(), InstallOutcome.openedForUser);
    });

    test('cubit: skipped version stays silent on automatic checks only', () async {
      final cubit = UpdateCubit(make());
      addTearDown(cubit.close);
      expect(await cubit.check(silent: true, skipped: '1.1.0'), isNull);
      expect(cubit.state.phase, UpdatePhase.upToDate);
      expect(await cubit.check(skipped: '1.1.0'), isNotNull, reason: 'manual check shows it');
    });

    test('cubit: silent checks swallow network errors; manual ones report them', () async {
      gh.rateLimited = true;
      final cubit = UpdateCubit(make());
      addTearDown(cubit.close);
      await cubit.check(silent: true);
      expect(cubit.state.phase, UpdatePhase.idle);
      await cubit.check();
      expect(cubit.state.phase, UpdatePhase.error);
      expect(cubit.state.errorCode, 'rateLimited');
    });

    test('local update: version comparison, sidecar checksum and wrong file type', () async {
      final cubit = UpdateCubit(make(current: '1.0.0'));
      addTearDown(cubit.close);
      final f = File(p.join(tmp.path, 'ZapDL-1.5.0-android.apk'))..writeAsBytesSync(apk);
      await cubit.useLocalFile(f);
      expect(cubit.state.phase, UpdatePhase.ready);
      expect(cubit.state.localNote, 'newer');
      expect(cubit.state.verified, isFalse, reason: 'no sidecar to verify against');

      File('${f.path}.sha256').writeAsStringSync('${sha256.convert(apk)}  ${p.basename(f.path)}\n');
      await cubit.useLocalFile(f);
      expect(cubit.state.verified, isTrue);

      File('${f.path}.sha256').writeAsStringSync('${'0' * 64}  ${p.basename(f.path)}\n');
      await cubit.useLocalFile(f);
      expect(cubit.state.phase, UpdatePhase.error);
      expect(cubit.state.errorCode, 'checksum');

      final exe = File(p.join(tmp.path, 'setup.exe'))..writeAsBytesSync([1]);
      await cubit.useLocalFile(exe);
      expect(cubit.state.errorCode, 'unsupported');

      final old = File(p.join(tmp.path, 'ZapDL-0.9.0-android.apk'))..writeAsBytesSync(apk);
      await cubit.useLocalFile(old);
      expect(cubit.state.localNote, 'older');
    });
  });
}
