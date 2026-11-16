import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/core/theme/app_fonts.dart';
import 'package:zapdl/features/settings/settings_cubit.dart';

void main() {
  test('every supported language has a bundled font and a direction', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^\s*-\s*family:\s*(\S+)', multiLine: true)
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toSet();
    for (final code in supportedLanguageCodes) {
      expect(declared, contains(AppFonts.familyFor(code)), reason: code);
      expect(AppFonts.fallbackFor(code), isNotEmpty);
    }
  });

  test('font files declared in pubspec exist on disk', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'asset:\s*(assets/\S+)')
        .allMatches(pubspec)
        .map((m) => m.group(1)!);
    expect(assets, isNotEmpty);
    for (final a in assets) {
      expect(File(a).existsSync(), isTrue, reason: a);
    }
  });

  test('Persian and Arabic are right-to-left; the others are left-to-right', () {
    expect(AppFonts.directionFor('fa'), TextDirection.rtl);
    expect(AppFonts.directionFor('ar'), TextDirection.rtl);
    for (final c in ['en', 'es', 'zh', 'ru']) {
      expect(AppFonts.directionFor(c), TextDirection.ltr, reason: c);
    }
  });

  test('Persian uses Vazirmatn', () => expect(AppFonts.familyFor('fa'), 'Vazirmatn'));
}
