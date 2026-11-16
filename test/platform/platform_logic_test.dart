import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapdl/engine/engine.dart';
import 'package:zapdl/engine/models.dart';
import 'package:zapdl/engine/store.dart';
import 'package:zapdl/features/settings/settings_cubit.dart';
import 'package:zapdl/platform/app_services.dart';
import 'package:zapdl/platform/background_service.dart';
import 'package:zapdl/platform/network_policy.dart';
import 'package:zapdl/platform/notifications.dart';
import 'package:zapdl/platform/url_import.dart';

class FakeNetwork implements NetworkSource {
  FakeNetwork(this.value);
  Set<ConnectionKind> value;
  final _c = StreamController<Set<ConnectionKind>>.broadcast();
  @override
  Future<Set<ConnectionKind>> current() async => value;
  @override
  Stream<Set<ConnectionKind>> get changes => _c.stream;
  void set(Set<ConnectionKind> v) {
    value = v;
    _c.add(v);
  }
}

class FakeNotifier implements AppNotifier {
  final shown = <(String, String)>[];
  @override
  Future<void> init({required String appName}) async {}
  @override
  Future<void> show({required String id, required String title, required String body}) async =>
      shown.add((title, body));
}

class FakeBackground implements BackgroundService {
  int updates = 0;
  int stops = 0;
  String? lastText;
  @override
  Future<void> update({required String title, required String text, int? progress}) async {
    updates++;
    lastText = text;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  group('network policy', () {
    test('Wi-Fi only refuses mobile data and allows Wi-Fi/Ethernet', () {
      expect(transfersAllowed({ConnectionKind.mobile}, wifiOnly: true), isFalse);
      expect(transfersAllowed({ConnectionKind.mobile}, wifiOnly: false), isTrue);
      expect(transfersAllowed({ConnectionKind.wifi}, wifiOnly: true), isTrue);
      expect(transfersAllowed({ConnectionKind.ethernet}, wifiOnly: true), isTrue);
      expect(transfersAllowed({ConnectionKind.wifi, ConnectionKind.other}, wifiOnly: true), isTrue);
      expect(transfersAllowed({ConnectionKind.other}, wifiOnly: true), isFalse);
    });

    test('offline is never allowed', () {
      expect(transfersAllowed({ConnectionKind.none}, wifiOnly: false), isFalse);
      expect(transfersAllowed({}, wifiOnly: false), isFalse);
    });

    test('mobile-only detection', () {
      expect(onMobileDataOnly({ConnectionKind.mobile}), isTrue);
      expect(onMobileDataOnly({ConnectionKind.mobile, ConnectionKind.wifi}), isFalse);
    });
  });

  group('URL import', () {
    test('extracts and de-duplicates URLs, trimming trailing punctuation', () {
      const text = 'See https://a.test/x.zip, and (https://b.test/y) also https://a.test/x.zip. '
          'Wiki: https://en.wikipedia.org/wiki/Foo_(bar) end';
      expect(extractUrls(text), [
        'https://a.test/x.zip',
        'https://b.test/y',
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      ]);
    });

    test('.url and .webloc shortcuts', () {
      expect(parseInternetShortcut('[InternetShortcut]\r\nURL=https://a.test/f.iso\r\n'),
          'https://a.test/f.iso');
      expect(parseInternetShortcut('nothing'), isNull);
      expect(
        parseWebloc('<dict><key>URL</key>\n<string>https://a.test/p?x=1&amp;y=2</string></dict>'),
        'https://a.test/p?x=1&y=2',
      );
    });

    test('files: txt list, .url, binary garbage, missing', () async {
      final dir = await Directory.systemTemp.createTemp('zapdl_drop');
      addTearDown(() => dir.delete(recursive: true));
      final txt = File(p.join(dir.path, 'links.txt'))
        ..writeAsStringSync('https://a.test/1\nnot a link\nhttps://a.test/2\n');
      final url = File(p.join(dir.path, 'x.url'))
        ..writeAsStringSync('[InternetShortcut]\nURL=https://a.test/3\n');
      final bin = File(p.join(dir.path, 'b.bin'))..writeAsBytesSync(List.filled(500, 0));
      expect(await urlsFromFile(txt.path), ['https://a.test/1', 'https://a.test/2']);
      expect(await urlsFromFile(url.path), ['https://a.test/3']);
      expect(await urlsFromFile(bin.path), isEmpty);
      expect(await urlsFromFile(p.join(dir.path, 'missing.txt')), isEmpty);
    });
  });

  group('AppServices', () {
    late Directory tmp;
    late DownloadEngine engine;
    late SettingsCubit settings;
    late FakeNetwork net;
    late FakeNotifier notifier;
    late FakeBackground bg;
    late AppServices services;

    Future<void> boot({Set<ConnectionKind>? kinds, bool suspend = false}) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tmp = await Directory.systemTemp.createTemp('zapdl_svc');
      engine = DownloadEngine(
        store: InMemoryDownloadStore(),
        partsRoot: p.join(tmp.path, 'parts'),
        tickInterval: const Duration(milliseconds: 30),
      );
      await engine.init();
      settings = SettingsCubit(prefs, engine, tmp.path);
      net = FakeNetwork(kinds ?? {ConnectionKind.wifi});
      notifier = FakeNotifier();
      bg = FakeBackground();
      services = AppServices(
        engine: engine,
        settings: settings,
        network: net,
        notifier: notifier,
        background: bg,
        suspendOnPause: suspend,
        backgroundThrottle: Duration.zero,
        texts: () => ServiceTexts(
          appName: 'ZapDL',
          completed: 'Done',
          failed: 'Failed',
          ongoing: (n, s) => '$n active',
        ),
      );
      await services.start();
    }

    tearDown(() async {
      await services.dispose();
      await settings.close();
      await engine.shutdown();
      await tmp.delete(recursive: true);
    });

    test('Wi-Fi-only on mobile data closes the engine gate; Wi-Fi reopens it', () async {
      await boot(kinds: {ConnectionKind.mobile});
      expect(engine.gate, EngineGate.open);
      settings.setWifiOnly(true);
      await Future<void>.delayed(Duration.zero);
      expect(engine.gate, EngineGate.network);
      net.set({ConnectionKind.wifi});
      await Future<void>.delayed(Duration.zero);
      expect(engine.gate, EngineGate.open);
    });

    test('going offline closes the gate and coming back reopens it', () async {
      await boot();
      net.set({ConnectionKind.none});
      await Future<void>.delayed(Duration.zero);
      expect(engine.gate, EngineGate.network);
      net.set({ConnectionKind.wifi});
      await Future<void>.delayed(Duration.zero);
      expect(engine.gate, EngineGate.open);
    });

    test('notifications can be turned off', () async {
      await boot();
      settings.setNotifications(false);
      expect(settings.state.notificationsEnabled, isFalse);
    });
  });
}
