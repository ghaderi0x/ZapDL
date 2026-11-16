import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/core/app_info.dart';
import 'package:zapdl/update/semver.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(appVersion, m!.group(1));
  });

  test('appVersion is a valid semantic version (the updater depends on it)', () {
    expect(SemVer.tryParse(appVersion), isNotNull);
  });

  test('the store build flag is off unless set at build time', () {
    expect(isStoreBuild, isFalse);
  });
}
