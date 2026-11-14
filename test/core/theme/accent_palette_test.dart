import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/core/theme/accent_palette.dart';
import 'package:zapdl/core/theme/app_theme.dart';
import 'package:zapdl/core/theme/zap_colors.dart';

void main() {
  group('AccentPalette', () {
    test('Electric Blue is the default and matches the brief', () {
      expect(AccentPalette.defaultPalette.id, 'electricBlue');
      expect(AccentPalette.electricBlue.primary, const Color(0xFF3478F6));
    });

    test('there are exactly four presets', () {
      expect(AccentPalette.presets.map((p) => p.id),
          ['electricBlue', 'royalPurple', 'emeraldGreen', 'sunsetOrange']);
    });

    test('preset serialization round-trips', () {
      for (final p in AccentPalette.presets) {
        expect(AccentPalette.deserialize(p.serialize()).id, p.id);
      }
    });

    test('custom color round-trips and keeps its primary hue', () {
      const picked = Color(0xFFE91E63);
      final custom = AccentPalette.fromColor(picked);
      final restored = AccentPalette.deserialize(custom.serialize());
      expect(restored.id, 'custom');
      expect(restored.primary.toARGB32(), custom.primary.toARGB32());
      expect(HSLColor.fromColor(custom.primary).hue,
          closeTo(HSLColor.fromColor(picked).hue, 1.0));
    });

    test('custom shades are ordered light to dark', () {
      final p = AccentPalette.fromColor(const Color(0xFF009688));
      double l(Color c) => HSLColor.fromColor(c).lightness;
      expect(l(p.shade50), greaterThan(l(p.shade200)));
      expect(l(p.shade200), greaterThan(l(p.shade300)));
      expect(l(p.shade300), greaterThan(l(p.shade500)));
      expect(l(p.shade500), greaterThan(l(p.shade700)));
    });

    test('invalid persisted value falls back to default', () {
      expect(AccentPalette.deserialize('custom:notanumber').id, 'electricBlue');
      expect(AccentPalette.deserialize('nope').id, 'electricBlue');
      expect(AccentPalette.deserialize(null).id, 'electricBlue');
    });
  });

  group('AppTheme', () {
    test('appearance and accent are independent', () {
      for (final p in AccentPalette.presets) {
        final dark = AppTheme.build(p, Brightness.dark);
        final light = AppTheme.build(p, Brightness.light);
        expect(dark.brightness, Brightness.dark);
        expect(light.brightness, Brightness.light);
        expect(dark.extension<ZapColors>()!.accent, p.primary);
        expect(light.extension<ZapColors>()!.accent, p.primary);
      }
    });

    test('text on accent meets at least 3:1 (large/bold UI text) for every preset', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final p in AccentPalette.presets) {
        final z = ZapColors.dark(p);
        // Documents actual behavior: some brand accents (e.g. orange/green)
        // may fall below 4.5:1 with either text color; this test will surface it.
        expect(ratio(z.accent, z.onAccent), greaterThanOrEqualTo(3.0),
            reason: '${p.id} onAccent contrast');
      }
    });
  });
}
