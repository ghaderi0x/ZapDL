import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/accent_palette.dart';
import '../../core/theme/zap_colors.dart';
import '../../l10n/gen/app_localizations.dart';
import 'settings_cubit.dart';

String _themeName(AppLocalizations l, String id) => switch (id) {
      'forest' => l.themeForest,
      'sunset' => l.themeSunset,
      'ocean' => l.themeOcean,
      _ => l.themeGlacier,
    };

String _themeDesc(AppLocalizations l, String id) => switch (id) {
      'forest' => l.themeForestDesc,
      'sunset' => l.themeSunsetDesc,
      'ocean' => l.themeOceanDesc,
      _ => l.themeGlacierDesc,
    };

/// Four theme cards with a small preview each, plus an Auto / Light / Dark
/// switch. Changes apply instantly (the whole app re-themes as you tap).
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    final cubit = context.read<SettingsCubit>();
    return BlocBuilder<SettingsCubit, SettingsState>(
      buildWhen: (a, b) => a.palette != b.palette || a.themeMode != b.themeMode,
      builder: (context, s) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, box) {
              const gap = 14.0;
              final w = (box.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final p in AccentPalette.themes)
                    SizedBox(
                      width: w,
                      child: _ThemeCard(
                        palette: p,
                        selected: s.palette.id == p.id,
                        title: _themeName(l, p.id),
                        subtitle: _themeDesc(l, p.id),
                        onTap: () => cubit.setPalette(p),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 20),
            Text(l.themeModeLabel, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _ModeSwitch(
              mode: s.themeMode,
              onChanged: cubit.setThemeMode,
              labels: (l.themeAuto, l.themeLight, l.themeDark),
              z: z,
            ),
          ],
        );
      },
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.onChanged,
    required this.labels,
    required this.z,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  final (String, String, String) labels;
  final ZapColors z;

  @override
  Widget build(BuildContext context) {
    Widget seg(ThemeMode m, String label) {
      final on = mode == m;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? z.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: on ? z.onAccent : z.text,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: z.surfaceRaised,
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(children: [
        seg(ThemeMode.system, labels.$1),
        seg(ThemeMode.light, labels.$2),
        seg(ThemeMode.dark, labels.$3),
      ]),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.palette,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final AccentPalette palette;
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    final accent = palette.primary;
    final tint = palette.tint ?? accent;
    final top = Color.alphaBlend(tint.withValues(alpha: 0.55), const Color(0xFF0A0B0D));
    const pill = Color(0xFF2A2C30);

    final preview = Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3A3D42)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, const Color(0xFF050506)],
          stops: const [0, 0.7],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.topEnd,
            child: Container(
              width: 64,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFB9BBB2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned.fill(
            top: 30,
            bottom: 36,
            child: Container(
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Row(children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: pill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          PositionedDirectional(
            top: 6,
            start: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.black,
                border: Border.all(color: Colors.black.withValues(alpha: 0.6)),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, size: 18, color: Colors.black)
                  : null,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: z.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: selected ? accent : z.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              preview,
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen version, shown at the end of first-run onboarding.
class ThemeChoosePage extends StatelessWidget {
  const ThemeChoosePage({super.key, required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final z = context.zap;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.1),
                radius: 1.0,
                colors: [z.glow, Colors.transparent],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.themeChooseTitle,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 32)),
                    const SizedBox(height: 8),
                    Text(l.themeChooseSubtitle,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: z.textMuted)),
                    const SizedBox(height: 28),
                    const ThemePicker(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                  onPressed: onConfirm,
                  child: Text(l.actionConfirm, style: const TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
