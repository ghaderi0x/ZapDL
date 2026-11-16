import 'package:flutter/painting.dart';

/// A five-step accent palette: [shade50] lightest ... [shade700] darkest.
/// [primary] is the brand/accent color (same as [shade500]).
class AccentPalette {
  const AccentPalette({
    required this.id,
    required this.shade50,
    required this.shade200,
    required this.shade300,
    required this.shade500,
    required this.shade700,
    this.tint,
    this.lightAccent,
  });

  final String id;
  final Color shade50;
  final Color shade200;
  final Color shade300;
  final Color shade500;
  final Color shade700;

  /// Named themes only: color the dark background leans toward.
  final Color? tint;

  /// Named themes only: darker accent used in light mode, where the bright
  /// dark-mode accent (lime, pale blue) would not be readable on white.
  final Color? lightAccent;

  Color get primary => shade500;

  /// Predefined themes from the product brief (section 5.1).
  static const electricBlue = AccentPalette(
    id: 'electricBlue',
    shade50: Color(0xFFEAF1FF),
    shade200: Color(0xFFBBD1FF),
    shade300: Color(0xFF82AAFF),
    shade500: Color(0xFF3478F6),
    shade700: Color(0xFF1E55C5),
  );

  static const royalPurple = AccentPalette(
    id: 'royalPurple',
    shade50: Color(0xFFF1ECFF),
    shade200: Color(0xFFD8CAFF),
    shade300: Color(0xFFAE94FF),
    shade500: Color(0xFF7955E8),
    shade700: Color(0xFF5633B9),
  );

  static const emeraldGreen = AccentPalette(
    id: 'emeraldGreen',
    shade50: Color(0xFFE4F8F1),
    shade200: Color(0xFFB8EBD9),
    shade300: Color(0xFF72D4B4),
    shade500: Color(0xFF0DAB83),
    shade700: Color(0xFF087D61),
  );

  static const sunsetOrange = AccentPalette(
    id: 'sunsetOrange',
    shade50: Color(0xFFFFF0E6),
    shade200: Color(0xFFFFD4B8),
    shade300: Color(0xFFFFAC7A),
    shade500: Color(0xFFF07835),
    shade700: Color(0xFFC7541F),
  );

  /// The four named themes of the theme picker (each works in light and dark).
  static const forest = AccentPalette(
    id: 'forest',
    shade50: Color(0xFFF1FADF),
    shade200: Color(0xFFDDF5A6),
    shade300: Color(0xFFD3F58A),
    shade500: Color(0xFFC3F060),
    shade700: Color(0xFF7FA82A),
    tint: Color(0xFF1F5A2C),
    lightAccent: Color(0xFF3F7A12),
  );

  static const sunset = AccentPalette(
    id: 'sunset',
    shade50: Color(0xFFFFF0E6),
    shade200: Color(0xFFFAD2B0),
    shade300: Color(0xFFF6B988),
    shade500: Color(0xFFF09C5A),
    shade700: Color(0xFFB8581D),
    tint: Color(0xFF6B2A1B),
    lightAccent: Color(0xFFBF500D),
  );

  static const ocean = AccentPalette(
    id: 'ocean',
    shade50: Color(0xFFE6F6FF),
    shade200: Color(0xFFBCE6FC),
    shade300: Color(0xFF9AD9FB),
    shade500: Color(0xFF6CC8F8),
    shade700: Color(0xFF1E88C8),
    tint: Color(0xFF123A8C),
    lightAccent: Color(0xFF0B6FB0),
  );

  static const glacier = AccentPalette(
    id: 'glacier',
    shade50: Color(0xFFF0F4FF),
    shade200: Color(0xFFDCE6FF),
    shade300: Color(0xFFEAF0FF),
    shade500: Color(0xFFDCE6FF),
    shade700: Color(0xFF8FA6E0),
    tint: Color(0xFF34436E),
    lightAccent: Color(0xFF3558C8),
  );

  static const themes = <AccentPalette>[forest, sunset, ocean, glacier];

  static const presets = <AccentPalette>[
    electricBlue,
    royalPurple,
    emeraldGreen,
    sunsetOrange,
  ];

  static const defaultPalette = electricBlue;

  static AccentPalette? presetById(String id) {
    for (final p in [...presets, ...themes]) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Derives a coordinated palette from any user-chosen color (section 5.2).
  ///
  /// Works in HSL so hue is preserved while lightness/saturation are tuned to
  /// roughly match the lightness ladder of the presets
  /// (50: ~95%, 200: ~86%, 300: ~76%, 500: the chosen color, 700: ~-16% L).
  factory AccentPalette.fromColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Clamp near-white / near-black picks so shades stay distinguishable.
    final base = hsl.withLightness(hsl.lightness.clamp(0.30, 0.65));
    Color shade(double lightness, {double satScale = 1.0}) => base
        .withLightness(lightness)
        .withSaturation((base.saturation * satScale).clamp(0.0, 1.0))
        .toColor();

    return AccentPalette(
      id: 'custom',
      shade50: shade(0.95, satScale: 1.0),
      shade200: shade(0.86, satScale: 0.95),
      shade300: shade(0.74, satScale: 0.95),
      shade500: base.toColor(),
      shade700: shade((base.lightness - 0.16).clamp(0.12, 0.5)),
    );
  }

  /// Serialization for persistence (custom colors must persist, section 5.2).
  /// Presets are stored by id; custom palettes by their primary ARGB value.
  String serialize() => id == 'custom' ? 'custom:${shade500.toARGB32()}' : id;

  static AccentPalette deserialize(String? raw) {
    if (raw == null || raw.isEmpty) return defaultPalette;
    if (raw.startsWith('custom:')) {
      final value = int.tryParse(raw.substring(7));
      if (value != null) return AccentPalette.fromColor(Color(value));
      return defaultPalette;
    }
    return presetById(raw) ?? defaultPalette;
  }
}
