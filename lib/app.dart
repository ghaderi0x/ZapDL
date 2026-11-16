import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/di.dart';
import 'core/platform.dart';
import 'core/theme/accent_palette.dart';
import 'core/theme/app_theme.dart';
import 'features/downloads/downloads_cubit.dart';
import 'features/downloads/url_history.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/settings/settings_cubit.dart';
import 'features/shell/adaptive_shell.dart';
import 'l10n/gen/app_localizations.dart';
import 'shared/app_builder.dart';
import 'update/update_cubit.dart';
import 'shared/widgets.dart';

/// Shows the splash while dependencies initialize, then the real app.
/// No artificial delay: the splash disappears as soon as startup finishes.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late final Future<void> _ready = configureDependencies();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
          return const ZapApp();
        }
        // Splash uses the default accent in dark mode; the full theme is not
        // available until settings load.
        final splashTheme = AppTheme.build(AccentPalette.defaultPalette, Brightness.dark);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: splashTheme,
          home: Builder(builder: (context) {
            return Scaffold(
              body: Center(
                child: snapshot.hasError
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${snapshot.error}', textAlign: TextAlign.center),
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ZapLogo(size: 88),
                          SizedBox(height: 16),
                          Text('ZapDL',
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            );
          }),
        );
      },
    );
  }
}

class ZapApp extends StatelessWidget {
  const ZapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<UrlHistory>.value(
      value: getIt<UrlHistory>(),
      child: MultiBlocProvider(
      providers: [
        BlocProvider<SettingsCubit>.value(value: getIt<SettingsCubit>()),
        BlocProvider<DownloadsCubit>.value(value: getIt<DownloadsCubit>()),
        BlocProvider<UpdateCubit>.value(value: getIt<UpdateCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, s) {
          return MaterialApp(
            title: 'ZapDL',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(s.palette, Brightness.light),
            darkTheme: AppTheme.build(s.palette, Brightness.dark),
            themeMode: s.themeMode,
            locale: s.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: zapAppBuilder,
            // Onboarding is a mobile experience; desktop goes straight in.
            home: (isMobilePlatform && !s.onboardingDone)
                ? const OnboardingPage()
                : const AdaptiveShell(),
          );
        },
      ),
      ),
    );
  }
}
