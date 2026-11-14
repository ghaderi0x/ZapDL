import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapdl/core/app_info.dart';
import 'package:zapdl/core/logger.dart';
import 'package:zapdl/features/downloads/url_history.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(appVersion, m!.group(1));
  });

  group('redactUrl', () {
    test('keeps only scheme and host', () {
      expect(
        redactUrl('https://user:pw@example.com:8080/a/b.zip?token=secret#frag'),
        'https://example.com',
      );
    });

    test('does not echo invalid input', () {
      expect(redactUrl('not a url with secret=1'), '<invalid-url>');
      expect(redactUrl(''), '<invalid-url>');
    });
  });

  group('UrlHistory', () {
    late UrlHistory history;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      history = UrlHistory(await SharedPreferences.getInstance());
    });

    test('is most-recent-first and de-duplicated', () async {
      await history.add('https://a.example/1');
      await history.add('https://b.example/2');
      await history.add('https://a.example/1');
      expect(history.items, ['https://a.example/1', 'https://b.example/2']);
    });

    test('ignores blanks and caps its size', () async {
      await history.add('   ');
      expect(history.items, isEmpty);
      for (var i = 0; i < UrlHistory.maxItems + 5; i++) {
        await history.add('https://example.com/$i');
      }
      expect(history.items.length, UrlHistory.maxItems);
      expect(history.items.first, 'https://example.com/${UrlHistory.maxItems + 4}');
    });

    test('clear removes everything', () async {
      await history.add('https://a.example/1');
      await history.clear();
      expect(history.items, isEmpty);
    });
  });
}
