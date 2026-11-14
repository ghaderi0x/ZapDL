import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/zap_colors.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/widgets.dart';
import '../settings/settings_cubit.dart';
import '../settings/theme_picker.dart';

/// Mobile-only first-run introduction. Skippable; shown once.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() => context.read<SettingsCubit>().completeOnboarding();

  /// Last step: pick a theme, then finish. (Confirm replaces the onboarding
  /// screen underneath, so the picker is popped to reveal the real home.)
  void _chooseTheme() {
    final settings = context.read<SettingsCubit>();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => BlocProvider.value(
        value: settings,
        child: ThemeChoosePage(onConfirm: () {
          settings.completeOnboarding();
          Navigator.of(ctx).maybePop();
        }),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final pages = [
      (Icons.dashboard_customize_rounded, l.onb1Title, l.onb1Body),
      (Icons.bolt_rounded, l.onb2Title, l.onb2Body),
      (Icons.pause_circle_outline_rounded, l.onb3Title, l.onb3Body),
      (Icons.folder_copy_outlined, l.onb4Title, l.onb4Body),
      (Icons.devices_rounded, l.onb5Title, l.onb5Body),
    ];
    final last = _index == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: _finish, child: Text(l.onbSkip)),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  final (icon, title, body) = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTile(icon: icon, size: 120),
                        const SizedBox(height: 32),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 12),
                        Text(body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: z.textMuted)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? z.accent : z.outline,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? _chooseTheme
                      : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                  child: Text(last ? l.onbStart : l.onbNext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
