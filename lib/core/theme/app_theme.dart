import 'package:flutter/material.dart';

import 'accent_palette.dart';
import 'zap_colors.dart';

/// Shape and spacing tokens (see docs/DESIGN_SPEC.md section 3).
abstract final class ZapRadii {
  static const double cardMobile = 28;
  static const double cardDesktop = 20;
  static const double iconTile = 16;
  static const double input = 14;
  static const double menu = 14;
  static const double window = 20;
}

abstract final class ZapSpacing {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24, xxxl = 32;
}

/// Builds the app [ThemeData] from an accent palette and brightness.
/// Rebuilding with a new palette/brightness switches the theme instantly
/// (MaterialApp animates ThemeData changes), with no restart.
abstract final class AppTheme {
  static ThemeData build(AccentPalette palette, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final z = isDark ? ZapColors.dark(palette) : ZapColors.light(palette);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: z.accent,
      onPrimary: z.onAccent,
      primaryContainer: z.accentContainer,
      onPrimaryContainer: z.onAccentContainer,
      secondary: z.accent,
      onSecondary: z.onAccent,
      error: z.error,
      onError: Colors.white,
      surface: z.surface,
      onSurface: z.text,
      onSurfaceVariant: z.textMuted,
      outline: z.outline,
      outlineVariant: z.outline,
      surfaceContainerHighest: z.surfaceRaised,
    );

    final stadium = const StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: z.background,
      extensions: [z],
      dividerTheme: DividerThemeData(color: z.outline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: z.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZapRadii.cardDesktop),
          side: BorderSide(color: z.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: z.accent,
          foregroundColor: z.onAccent,
          shape: stadium,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: z.text,
          side: BorderSide(color: z.outline),
          shape: stadium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: z.surfaceRaised,
        hintStyle: TextStyle(color: z.textMuted),
        contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZapRadii.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZapRadii.input),
          borderSide: BorderSide(color: z.accent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: z.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZapRadii.window),
          side: BorderSide(color: z.outline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: z.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZapRadii.cardMobile)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: z.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZapRadii.menu),
          side: BorderSide(color: z.outline),
        ),
      ),
      // Desktop pointer feedback: hover and focus tints on every tappable.
      hoverColor: z.accent.withValues(alpha: 0.08),
      focusColor: z.accent.withValues(alpha: 0.12),
      splashColor: z.accent.withValues(alpha: 0.12),
      highlightColor: z.accent.withValues(alpha: 0.06),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.hovered)) return z.accent.withValues(alpha: 0.14);
            if (s.contains(WidgetState.pressed)) return z.accent.withValues(alpha: 0.2);
            return null;
          }),
        ),
      ),
      // Readable on every theme; floating so it sits above the add button
      // instead of covering it.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF14161A) : z.surfaceRaised,
        contentTextStyle: TextStyle(color: isDark ? Colors.white : z.text, fontSize: 14),
        actionTextColor: z.accent,
        showCloseIcon: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZapRadii.input),
          side: BorderSide(color: z.outline),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: z.accent,
        linearTrackColor: z.outline,
      ),
      iconTheme: IconThemeData(color: z.textMuted, size: 22),
      textTheme: _textTheme(z),
    );
  }

  static TextTheme _textTheme(ZapColors z) {
    // Tabular figures keep speed/percent readouts from jittering while updating.
    const tabular = [FontFeature.tabularFigures()];
    return TextTheme(
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: z.text),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: z.text),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: z.text),
      bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: z.text),
      bodyMedium: TextStyle(fontSize: 14, color: z.text),
      bodySmall: TextStyle(fontSize: 12, color: z.textMuted, fontFeatures: tabular),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: z.text),
      labelSmall: TextStyle(fontSize: 12, color: z.textMuted, fontFeatures: tabular),
    );
  }
}
