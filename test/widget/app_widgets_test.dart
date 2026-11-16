import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapdl/core/theme/accent_palette.dart';
import 'package:zapdl/core/theme/app_theme.dart';
import 'package:zapdl/core/theme/zap_colors.dart';
import 'package:zapdl/engine/engine.dart';
import 'package:zapdl/engine/models.dart';
import 'package:zapdl/engine/store.dart';
import 'package:zapdl/features/downloads/download_items.dart';
import 'package:zapdl/features/downloads/downloads_cubit.dart';
import 'package:zapdl/features/downloads/downloads_page.dart';
import 'package:zapdl/features/downloads/url_history.dart';
import 'package:zapdl/features/settings/settings_cubit.dart';
import 'package:zapdl/features/settings/settings_page.dart';
import 'package:zapdl/l10n/gen/app_localizations.dart';
import 'package:zapdl/shared/app_builder.dart';
import 'package:zapdl/update/asset_selector.dart';
import 'package:zapdl/update/semver.dart';
import 'package:zapdl/update/update_cubit.dart';
import 'package:zapdl/update/update_service.dart';

/// Mini version of ZapApp that avoids the global service locator.
class _NoInstaller implements UpdateInstaller {
  @override
  Future<InstallOutcome> install(String path, UpdatePlatform platform) async =>
      InstallOutcome.revealed;
}

class _Harness {
  _Harness(this.engine, this.settings, this.downloads, this.history, this.updates);

  final DownloadEngine engine;
  final SettingsCubit settings;
  final DownloadsCubit downloads;
  final UrlHistory history;
  final UpdateCubit updates;

  static Future<_Harness> create(Directory tmp) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final engine = DownloadEngine(
      store: InMemoryDownloadStore(),
      partsRoot: p.join(tmp.path, 'parts'),
    );
    return _Harness(
      engine,
      SettingsCubit(prefs, engine, p.join(tmp.path, 'dl')),
      DownloadsCubit(engine),
      UrlHistory(prefs),
      UpdateCubit(UpdateService(
        prefs: prefs,
        currentVersion: const SemVer(0, 1, 0),
        updatesDir: p.join(tmp.path, 'updates'),
        platform: UpdatePlatform.linux,
        arch: 'x64',
        installer: _NoInstaller(),
      )),
    );
  }

  Widget app(Widget home, {Locale? locale}) {
    return RepositoryProvider<UrlHistory>.value(
      value: history,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>.value(value: settings),
          BlocProvider<DownloadsCubit>.value(value: downloads),
          BlocProvider<UpdateCubit>.value(value: updates),
        ],
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (context, s) => MaterialApp(
            theme: AppTheme.build(s.palette, Brightness.light),
            darkTheme: AppTheme.build(s.palette, Brightness.dark),
            themeMode: s.themeMode,
            locale: locale ?? s.locale ?? const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: zapAppBuilder,
            home: Scaffold(body: home),
          ),
        ),
      ),
    );
  }
}

void main() {
  late Directory tmp;
  late _Harness h;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('zapdl_widget');
    h = await _Harness.create(tmp);
  });

  tearDown(() async {
    await h.downloads.close();
    await h.updates.close();
    await h.settings.close();
    await h.engine.shutdown();
    await tmp.delete(recursive: true);
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('dashboard shows the empty state with an add action', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(h.app(const DownloadsPage(wide: false)));
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet'), findsOneWidget);
    expect(find.text('Add download'), findsOneWidget);
  });

  testWidgets('wide dashboard shows the desktop status bar', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(h.app(const DownloadsPage(wide: true)));
    await tester.pumpAndSettle();
    expect(find.text('0 active'), findsOneWidget);
  });

  testWidgets('download card shows name, percent and speed for an active download',
      (tester) async {
    bigScreen(tester);
    final task = DownloadTask(
      id: 't1',
      url: 'https://example.com/movie.mp4',
      fileName: 'movie.mp4',
      directory: tmp.path,
      totalBytes: 1000,
      receivedBytes: 500,
      status: DownloadStatus.downloading,
      speedBps: 100,
    );
    await tester.pumpWidget(h.app(Center(child: SizedBox(width: 420, child: DownloadCard(task: task)))));
    await tester.pumpAndSettle();
    expect(find.text('movie.mp4'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Downloading'), findsOneWidget);
  });

  testWidgets('failed download card shows a meaningful localized error', (tester) async {
    bigScreen(tester);
    final task = DownloadTask(
      id: 't2',
      url: 'https://example.com/a.zip',
      fileName: 'a.zip',
      directory: tmp.path,
      status: DownloadStatus.failed,
      errorCode: DownloadErrorCode.network,
    );
    await tester.pumpWidget(h.app(Center(child: SizedBox(width: 420, child: DownloadCard(task: task)))));
    await tester.pumpAndSettle();
    expect(find.text('Network problem. Check your connection.'), findsOneWidget);
  });

  testWidgets('Persian locale uses a right-to-left layout and Persian text', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
      h.app(const DownloadsPage(wide: false), locale: const Locale('fa')),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(DownloadsPage));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text('هنوز دانلودی نیست'), findsOneWidget);
  });

  testWidgets('each language gets its own font and direction', (tester) async {
    bigScreen(tester);
    final expected = {
      'en': ('Inter', TextDirection.ltr),
      'es': ('Inter', TextDirection.ltr),
      'ru': ('Inter', TextDirection.ltr),
      'zh': ('NotoSansSC', TextDirection.ltr),
      'fa': ('Vazirmatn', TextDirection.rtl),
      'ar': ('Vazirmatn', TextDirection.rtl),
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(
        h.app(const DownloadsPage(wide: false), locale: Locale(entry.key)),
      );
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(DownloadsPage));
      expect(Directionality.of(ctx), entry.value.$2, reason: entry.key);
      expect(Theme.of(ctx).textTheme.bodyMedium?.fontFamily, entry.value.$1,
          reason: entry.key);
    }
  });

  testWidgets('English locale uses a left-to-right layout', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(h.app(const DownloadsPage(wide: false)));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(DownloadsPage));
    expect(Directionality.of(ctx), TextDirection.ltr);
  });

  testWidgets('settings: choosing Dark switches the theme and persists it', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(h.app(const SettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(h.settings.state.themeMode, ThemeMode.dark);
    final ctx = tester.element(find.byType(SettingsPage));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('themeMode'), 'dark');
  });

  testWidgets('accent change keeps the appearance mode and updates colors', (tester) async {
    bigScreen(tester);
    h.settings.setThemeMode(ThemeMode.light);
    await tester.pumpWidget(h.app(const SettingsPage()));
    await tester.pumpAndSettle();
    h.settings.setPalette(AccentPalette.royalPurple);
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(SettingsPage));
    expect(h.settings.state.themeMode, ThemeMode.light);
    expect(Theme.of(ctx).brightness, Brightness.light);
    expect(ctx.zap.accent, AccentPalette.royalPurple.primary);
  });

  testWidgets('settings: switching language re-renders strings and persists', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(h.app(const SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    h.settings.setLanguage('es');
    await tester.pumpAndSettle();
    expect(find.text('Apariencia'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('language'), 'es');
  });
}
