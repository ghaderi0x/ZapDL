import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/zap_colors.dart';
import '../engine/file_category.dart';
import '../features/settings/settings_cubit.dart';
import '../l10n/gen/app_localizations.dart';

/// Rounded, outlined surface used for every grouped section (refs R1, R4, R5).
class ZapCard extends StatelessWidget {
  const ZapCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZapSpacing.lg),
    this.radius = ZapRadii.cardDesktop,
    this.color,
    this.onTap,
    this.onSecondaryTapDown,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    // Material (not a colored Container) so ListTile/InkWell children can
    // paint their ink and background on it.
    return Material(
      color: color ?? z.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: z.outline),
      ),
      child: onTap == null && onSecondaryTapDown == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              onSecondaryTapDown: onSecondaryTapDown,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// 6 dp rounded bar with accent-derived gradient fill (refs R2, R3).
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({
    super.key,
    required this.value,
    this.solidColor,
    this.height = 6,
  });

  /// 0..1, or null for an indeterminate (unknown size) bar.
  final double? value;
  final Color? solidColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Screen readers announce the percentage; the bar itself is decorative.
    return Semantics(
      value: value == null ? null : '${(value! * 100).round()}%',
      child: ExcludeSemantics(child: _bar(context)),
    );
  }

  Widget _bar(BuildContext context) {
    final z = context.zap;
    if (value == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          minHeight: height,
          color: solidColor ?? z.accent,
          backgroundColor: z.outline,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: z.outline,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: value!.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: solidColor,
              gradient: solidColor == null ? z.progressGradient : null,
              borderRadius: BorderRadius.circular(height),
            ),
            child: SizedBox(height: height),
          ),
        ),
      ),
    );
  }
}

/// Small rounded pill (ref R3 chips).
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, this.icon, this.filled = false});

  final String label;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    final fg = filled ? z.onAccent : z.textMuted;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? z.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: z.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Accent-tinted rounded square holding an icon (ref R1 icon tiles).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 44, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final z = context.zap;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: z.accentContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? z.accent),
    );
  }
}

IconData categoryIcon(FileCategory c) => switch (c) {
      FileCategory.video => Icons.movie_outlined,
      FileCategory.audio => Icons.music_note_outlined,
      FileCategory.image => Icons.image_outlined,
      FileCategory.document => Icons.description_outlined,
      FileCategory.archive => Icons.folder_zip_outlined,
      FileCategory.application => Icons.apps_outlined,
      FileCategory.other => Icons.insert_drive_file_outlined,
    };

/// App mark: bolt in an accent gradient tile.
class ZapLogo extends StatelessWidget {
  const ZapLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    // The official ZapDL icon (already a rounded square with transparency).
    return Image.asset(
      'assets/icon/zapdl.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ZapDL',
    );
  }
}


/// Small sun/moon button: flips between light and dark (an explicit choice,
/// replacing "system"; Auto stays available in Settings).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final l = AppLocalizations.of(context);
    return IconButton(
      tooltip: dark ? l.themeLight : l.themeDark,
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          context.read<SettingsCubit>().setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
