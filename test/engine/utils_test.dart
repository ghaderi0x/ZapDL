import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zapdl/engine/checksum.dart';
import 'package:zapdl/engine/errors.dart';
import 'package:zapdl/engine/file_category.dart';
import 'package:zapdl/engine/file_utils.dart';
import 'package:zapdl/engine/models.dart';
import 'package:zapdl/engine/probe.dart';

void main() {
  group('sanitizeFileName', () {
    test('strips directories (path traversal)', () {
      expect(sanitizeFileName('../../etc/passwd'), 'passwd');
      expect(sanitizeFileName(r'..\..\windows\system32\evil.dll'), 'evil.dll');
      expect(sanitizeFileName('/abs/path/file.zip'), 'file.zip');
    });

    test('replaces invalid characters', () {
      expect(sanitizeFileName('a<b>c:d"e|f?g*h.txt'), 'a_b_c_d_e_f_g_h.txt');
    });

    test('never returns empty or dot-only names', () {
      expect(sanitizeFileName(''), 'download');
      expect(sanitizeFileName('...'), 'download');
      expect(sanitizeFileName('  '), 'download');
    });

    test('avoids reserved Windows names', () {
      expect(sanitizeFileName('CON.txt'), '_CON.txt');
      expect(sanitizeFileName('nul'), '_nul');
    });

    test('caps very long names but keeps the extension', () {
      final name = '${'a' * 500}.mp4';
      final out = sanitizeFileName(name);
      expect(out.length, lessThanOrEqualTo(200));
      expect(out.endsWith('.mp4'), isTrue);
    });
  });

  test('uniquePath adds a counter instead of overwriting', () async {
    final dir = await Directory.systemTemp.createTemp('zapdl_unique');
    addTearDown(() => dir.delete(recursive: true));
    expect(uniquePath(dir.path, 'a.zip'), p.join(dir.path, 'a.zip'));
    await File(p.join(dir.path, 'a.zip')).writeAsString('x');
    expect(uniquePath(dir.path, 'a.zip'), p.join(dir.path, 'a (1).zip'));
    await File(p.join(dir.path, 'a (1).zip')).writeAsString('x');
    expect(uniquePath(dir.path, 'a.zip'), p.join(dir.path, 'a (2).zip'));
  });

  group('categoryFor', () {
    test('uses extension first', () {
      expect(categoryFor('movie.MKV'), FileCategory.video);
      expect(categoryFor('song.flac'), FileCategory.audio);
      expect(categoryFor('pic.webp'), FileCategory.image);
      expect(categoryFor('paper.pdf'), FileCategory.document);
      expect(categoryFor('bundle.tar'), FileCategory.archive);
      expect(categoryFor('setup.exe'), FileCategory.application);
      expect(categoryFor('mystery.xyz'), FileCategory.other);
    });

    test('falls back to MIME type', () {
      expect(categoryFor('download', mime: 'video/mp4'), FileCategory.video);
      expect(categoryFor('download', mime: 'audio/mpeg'), FileCategory.audio);
      expect(categoryFor('download', mime: 'application/zip'), FileCategory.archive);
      expect(categoryFor('download', mime: 'application/octet-stream'), FileCategory.other);
    });
  });

  group('URL handling', () {
    test('accepts http/https', () {
      expect(parseDownloadUri('https://example.com/a.zip').host, 'example.com');
      expect(parseDownloadUri('  http://example.com/a  ').scheme, 'http');
    });

    test('rejects invalid input', () {
      for (final bad in ['', 'not a url', 'example.com/file', 'file:///etc/passwd', 'javascript:alert(1)']) {
        expect(
          () => parseDownloadUri(bad),
          throwsA(isA<DownloadFailure>().having((f) => f.code, 'code', DownloadErrorCode.invalidUrl)),
          reason: bad,
        );
      }
    });

    test('reports ftp/sftp as unsupported, not invalid', () {
      expect(
        () => parseDownloadUri('ftp://example.com/a.zip'),
        throwsA(isA<DownloadFailure>()
            .having((f) => f.code, 'code', DownloadErrorCode.unsupportedScheme)),
      );
      expect(
        () => parseDownloadUri('sftp://example.com/a.zip'),
        throwsA(isA<DownloadFailure>()
            .having((f) => f.code, 'code', DownloadErrorCode.unsupportedScheme)),
      );
    });

    test('looksLikeDownloadUrl is strict about whitespace and scheme', () {
      expect(looksLikeDownloadUrl('https://example.com/a.zip'), isTrue);
      expect(looksLikeDownloadUrl('see https://example.com'), isFalse);
      expect(looksLikeDownloadUrl('ftp://example.com/a'), isFalse);
      expect(looksLikeDownloadUrl('hello'), isFalse);
    });

    test('parseContentDisposition handles plain and RFC 5987 forms', () {
      expect(parseContentDisposition('attachment; filename="report.pdf"'), 'report.pdf');
      expect(parseContentDisposition('attachment; filename=report.pdf'), 'report.pdf');
      expect(
        parseContentDisposition("attachment; filename*=UTF-8''na%C3%AFve%20file.txt"),
        'naïve file.txt',
      );
      expect(parseContentDisposition(null), isNull);
    });
  });

  group('planSegments', () {
    test('splits evenly and covers every byte exactly once', () {
      const total = 10 * 1024 * 1024 + 7;
      final segs = planSegments(
        total: total,
        ranges: true,
        connections: 4,
        minSegmentBytes: 1024 * 1024,
      );
      expect(segs.length, 4);
      expect(segs.first.start, 0);
      expect(segs.last.end, total - 1);
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].start, segs[i - 1].end + 1);
      }
      expect(segs.fold<int>(0, (a, s) => a + s.length), total);
    });

    test('falls back to one connection without range support', () {
      final segs = planSegments(
        total: 50 * 1024 * 1024,
        ranges: false,
        connections: 8,
        minSegmentBytes: 1024 * 1024,
      );
      expect(segs.length, 1);
      expect(segs.single.length, 50 * 1024 * 1024);
    });

    test('small files use a single segment', () {
      final segs = planSegments(
        total: 500 * 1024,
        ranges: true,
        connections: 8,
        minSegmentBytes: 1024 * 1024,
      );
      expect(segs.length, 1);
    });

    test('unknown length is a single open-ended segment', () {
      final segs = planSegments(total: -1, ranges: false, connections: 4, minSegmentBytes: 1);
      expect(segs.length, 1);
      expect(segs.single.end, -1);
    });
  });

  test('DownloadTask JSON round-trips including segments and error', () {
    final t = DownloadTask(
      id: 'abc',
      url: 'https://example.com/a.zip',
      fileName: 'a.zip',
      directory: '/tmp',
      totalBytes: 1000,
      receivedBytes: 400,
      status: DownloadStatus.failed,
      errorCode: DownloadErrorCode.changed,
      needsRestart: true,
      etag: '"x"',
      rangeSupported: true,
      segments: [Segment(start: 0, end: 499, received: 400), Segment(start: 500, end: 999)],
    );
    final copy = DownloadTask.fromJson(
      (jsonDecode(jsonEncode(t.toJson())) as Map).cast<String, dynamic>(),
    );
    expect(copy.id, 'abc');
    expect(copy.status, DownloadStatus.failed);
    expect(copy.errorCode, DownloadErrorCode.changed);
    expect(copy.needsRestart, isTrue);
    expect(copy.segments.length, 2);
    expect(copy.segments.first.received, 400);
    expect(copy.etag, '"x"');
  });

  test('checksums are calculated and verified correctly', () async {
    final dir = await Directory.systemTemp.createTemp('zapdl_sum');
    addTearDown(() => dir.delete(recursive: true));
    final f = File(p.join(dir.path, 'x.txt'));
    await f.writeAsString('abc');
    expect(
      await calculateChecksum(f, ChecksumAlgorithm.sha256),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      await calculateChecksum(f, ChecksumAlgorithm.md5),
      '900150983cd24fb0d6963f7d28e17f72',
    );
    expect(
      await verifyChecksum(f, ChecksumAlgorithm.md5, '900150983CD24FB0D6963F7D28E17F72'),
      isTrue,
    );
    expect(await verifyChecksum(f, ChecksumAlgorithm.sha256, 'deadbeef'), isFalse);
  });
}
