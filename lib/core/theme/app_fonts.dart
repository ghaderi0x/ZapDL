import 'package:flutter/material.dart';

/// Per-language typography and text direction.
///
/// Fonts are bundled (see assets/fonts/LICENSES.txt), so the app looks the
/// same offline and on every platform:
///  - Persian, Arabic: Vazirmatn (also contains Latin glyphs for mixed text)
///  - English, Spanish, Russian: Inter (Latin, Latin Extended, Cyrillic)
///  - Chinese: Noto Sans SC subset, then the system CJK font for rare hanzi
abstract final class AppFonts {
  static const vazirmatn = 'Vazirmatn';
  static const inter = 'Inter';
  static const notoSansSc = 'NotoSansSC';

  /// Every family declared in pubspec.yaml (checked by a test).
  static const bundledFamilies = [vazirmatn, inter, notoSansSc];

  static const _rtlLanguages = {'fa', 'ar', 'he', 'ur'};

  static const _systemCjk = [
    'PingFang SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Source Han Sans SC',
  ];

  static String familyFor(String languageCode) => switch (languageCode) {
        'fa' || 'ar' => vazirmatn,
        'zh' => notoSansSc,
        _ => inter,
      };

  /// File names and URLs can contain any script, so every language falls back
  /// to the other bundled families and then to system CJK fonts.
  static List<String> fallbackFor(String languageCode) {
    final primary = familyFor(languageCode);
    return [
      for (final f in bundledFamilies)
        if (f != primary) f,
      ..._systemCjk,
    ];
  }

  static TextDirection directionFor(String languageCode) =>
      _rtlLanguages.contains(languageCode) ? TextDirection.rtl : TextDirection.ltr;

  /// Returns [base] with the language's font family applied to every text style.
  static ThemeData applyTo(ThemeData base, String languageCode) {
    final family = familyFor(languageCode);
    final fallback = fallbackFor(languageCode);
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: family, fontFamilyFallback: fallback),
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamily: family, fontFamilyFallback: fallback),
    );
  }
}
