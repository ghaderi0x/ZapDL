import 'package:flutter/material.dart';

import 'accent_palette.dart';

/// Design tokens that Material's [ColorScheme] does not model: layered
/// surfaces, semantic status colors and the accent-derived progress gradient.
/// Widgets read these via `context.zap` instead of hardcoding colors.
@immutable
class ZapColors extends ThemeExtension<ZapColors> {
  const ZapColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.success,
    required this.warning,
    required this.error,
    required this.progressGradient,
    required this.glow,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color outline;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color success;
  final Color warning;
  final Color error;
  final LinearGradient progressGradient;

  /// Subtle radial glow at the top of mobile screens (reference R1).
  final Color glow;

  static ZapColors dark(AccentPalette p) => ZapColors(
        // Neutral near-black with a 3% accent tint, as in R7/R1.
        background: Color.alphaBlend(
            (p.tint ?? p.primary).withValues(alpha: p.tint != null ? 0.16 : 0.03),
            const Color(0xFF0E0F12)),
        surface: const Color(0xFF17191D),
        surfaceRaised: const Color(0xFF1E2126),
        outline: const Color(0xFF2A2D33),
        text: const Color(0xFFF2F4F7),
        textMuted: const Color(0xFF9AA1AD),
        accent: p.primary,
        onAccent: _onColor(p.primary),
        accentContainer: Color.alphaBlend(p.primary.withValues(alpha: 0.18), const Color(0xFF17191D)),
        onAccentContainer: p.shade300,
        success: const Color(0xFF2EC27E),
        warning: const Color(0xFFF5B93B),
        error: const Color(0xFFF0616D),
        progressGradient: LinearGradient(colors: [p.primary, p.shade300]),
        glow: (p.tint ?? p.primary).withValues(alpha: p.tint != null ? 0.35 : 0.10),
      );

  static ZapColors light(AccentPalette p) {
    final a = p.lightAccent ?? p.primary;
    return ZapColors(
        background: Color.alphaBlend(a.withValues(alpha: 0.03), const Color(0xFFF3F6FB)),
        surface: const Color(0xFFFFFFFF),
        surfaceRaised: const Color(0xFFEEF2F8),
        outline: const Color(0xFFDDE3EC),
        text: const Color(0xFF14181F),
        textMuted: const Color(0xFF5B6472),
        accent: a,
        onAccent: _onColor(a),
        accentContainer: p.lightAccent != null ? a.withValues(alpha: 0.14) : p.shade50,
        onAccentContainer: p.lightAccent != null ? a : p.shade700,
        success: const Color(0xFF12945A),
        warning: const Color(0xFFB7791F),
        error: const Color(0xFFC0343F),
        progressGradient: LinearGradient(colors: [p.lightAccent ?? p.shade700, a]),
        glow: a.withValues(alpha: 0.08),
      );
  }

  /// Picks text color for an accent background. White is preferred (it matches
  /// the reference designs) as long as it reaches 3:1, the WCAG minimum for
  /// large/bold UI text; otherwise near-black is used so bright custom accents
  /// (e.g. yellow) and light presets stay readable.
  static Color _onColor(Color bg) {
    final l = bg.computeLuminance();
    final contrastWhite = 1.05 / (l + 0.05);
    return contrastWhite >= 3.0 ? Colors.white : const Color(0xFF0E0F12);
  }

  @override
  ZapColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? outline,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? success,
    Color? warning,
    Color? error,
    LinearGradient? progressGradient,
    Color? glow,
  }) =>
      ZapColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        outline: outline ?? this.outline,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentContainer: accentContainer ?? this.accentContainer,
        onAccentContainer: onAccentContainer ?? this.onAccentContainer,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        progressGradient: progressGradient ?? this.progressGradient,
        glow: glow ?? this.glow,
      );

  @override
  ZapColors lerp(ThemeExtension<ZapColors>? other, double t) {
    if (other is! ZapColors) return this;
    return ZapColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(onAccentContainer, other.onAccentContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      progressGradient: LinearGradient.lerp(progressGradient, other.progressGradient, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}

extension ZapThemeContext on BuildContext {
  ZapColors get zap => Theme.of(this).extension<ZapColors>()!;
}
