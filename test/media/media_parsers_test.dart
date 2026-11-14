import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/media/adapters.dart';
import 'package:zapdl/media/media_models.dart';
import 'package:zapdl/media/resolver.dart';

// Samples are hand-written to mirror the documented shape of each source.
// They prove the parsers, NOT that the live sites still use these shapes.
void main() {
  group('Reddit', () {
    final video = jsonEncode([
      {
        'data': {
          'children': [
            {
              'data': {
                'title': 'A clip',
                'author': 'someone',
                'secure_media': {
                  'reddit_video': {
                    'fallback_url': 'https://v.redd.it/abc/DASH_720.mp4?source=fallback',
                    'height': 720,
                    'has_audio': true,
                  }
                }
              }
            }
          ]
        }
      }
    ]);

    test('video post: video-only format is labeled honestly, audio offered separately', () {
      final info = parseRedditJson(video, 'https://reddit.com/r/x/comments/1/a');
      expect(info.title, 'A clip');
      expect(info.formats.map((f) => f.id), ['video', 'audio']);
      expect(info.formats.first.url, 'https://v.redd.it/abc/DASH_720.mp4');
      expect(info.formats.first.note, 'videoOnlyNoSound');
      expect(info.formats.last.url, 'https://v.redd.it/abc/DASH_AUDIO_128.mp4');
      expect(info.formats.last.isAudioOnly, isTrue);
    });

    test('gallery post lists every image with unescaped URLs', () {
      final body = jsonEncode([
        {
          'data': {
            'children': [
              {
                'data': {
                  'title': 'g',
                  'is_gallery': true,
                  'media_metadata': {
                    'a': {'s': {'u': 'https://preview.redd.it/a.jpg?w=1&amp;s=2'}},
                    'b': {'s': {'u': 'https://preview.redd.it/b.png'}},
                  }
                }
              }
            ]
          }
        }
      ]);
      final info = parseRedditJson(body, 'https://reddit.com/x');
      expect(info.formats, hasLength(2));
      expect(info.formats.first.url, 'https://preview.redd.it/a.jpg?w=1&s=2');
      expect(info.formats.every((f) => f.isImage), isTrue);
      expect(info.formats.last.extension, 'png');
    });

    test('text-only post and garbage report clean errors', () {
      final text = jsonEncode([
        {
          'data': {
            'children': [
              {'data': {'title': 't'}}
            ]
          }
        }
      ]);
      expect(() => parseRedditJson(text, 'u'),
          throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'notFound')));
      expect(() => parseRedditJson('<html>', 'u'),
          throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'parse')));
    });
  });

  group('Telegram embed', () {
    const html = '''
<div class="tgme_widget_message_text js-message_text">Hello <b>world</b> &amp; co</div>
<video src="https://cdn4.cdn-telegram.org/file/abc.mp4?x=1&amp;y=2" class="x"></video>
<a class="tgme_widget_message_photo_wrap" style="width:100px;background-image:url('https://cdn4.cdn-telegram.org/file/p.jpg')"></a>
''';
    test('extracts video and photo', () {
      final info = parseTelegramEmbed(html, 'https://t.me/chan/5');
      expect(info.title, 'Hello world & co');
      expect(info.formats.first.url, 'https://cdn4.cdn-telegram.org/file/abc.mp4?x=1&y=2');
      expect(info.formats.last.isImage, isTrue);
    });

    test('empty embed is not found', () {
      expect(() => parseTelegramEmbed('<div></div>', 'u'), throwsA(isA<MediaException>()));
    });
  });

  group('Open Graph', () {
    test('og:video wins and relative URLs resolve', () {
      const html = '''
<html><head><title>Fallback</title>
<meta property="og:title" content="My &quot;clip&quot;">
<meta content="/media/v.mp4" property="og:video">
<meta property="og:image" content="https://x.test/t.jpg">
</head><body><video><source src="/media/v2.webm"></video></body></html>''';
      final info = parseOpenGraph(html, 'https://x.test/watch/1');
      expect(info.title, 'My "clip"');
      expect(info.formats.map((f) => f.url), [
        'https://x.test/media/v.mp4',
        'https://x.test/media/v2.webm',
      ]);
      expect(info.thumbnail, 'https://x.test/t.jpg');
    });

    test('image-only pages offer the image; empty pages are unsupported', () {
      final img = parseOpenGraph(
          '<meta property="og:image" content="https://x.test/a.png">', 'https://x.test/p');
      expect(img.formats.single.isImage, isTrue);
      expect(() => parseOpenGraph('<html></html>', 'https://x.test/p'),
          throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'unsupported')));
    });

    test('embedded player pages are not offered as files', () {
      expect(
        () => parseOpenGraph(
            '<meta property="og:video" content="https://x.test/player.html">', 'https://x.test/'),
        throwsA(isA<MediaException>()),
      );
    });
  });

  group('yt-dlp JSON', () {
    test('keeps direct http formats, drops manifests, best muxed first', () {
      final body = jsonEncode({
        'title': 'T',
        'extractor_key': 'Vimeo',
        'duration': 61,
        'formats': [
          {'format_id': 'hls', 'url': 'https://a/m.m3u8', 'protocol': 'm3u8_native', 'vcodec': 'avc1', 'acodec': 'mp4a'},
          {'format_id': '360', 'url': 'https://a/360.mp4', 'protocol': 'https', 'vcodec': 'avc1', 'acodec': 'mp4a', 'height': 360, 'ext': 'mp4'},
          {'format_id': '720', 'url': 'https://a/720.mp4', 'protocol': 'https', 'vcodec': 'avc1', 'acodec': 'mp4a', 'height': 720, 'ext': 'mp4', 'filesize': 1000, 'http_headers': {'Referer': 'https://a/', 'Accept-Encoding': 'gzip'}},
          {'format_id': 'v1080', 'url': 'https://a/1080.mp4', 'protocol': 'https', 'vcodec': 'avc1', 'acodec': 'none', 'height': 1080, 'ext': 'mp4'},
          {'format_id': 'aud', 'url': 'https://a/a.m4a', 'protocol': 'https', 'vcodec': 'none', 'acodec': 'mp4a', 'abr': 128.4, 'ext': 'm4a'},
        ],
      });
      final info = parseYtDlpJson(body, 'https://vimeo.com/1');
      expect(info.platform, 'Vimeo');
      expect(info.duration, const Duration(seconds: 61));
      expect(info.formats.map((f) => f.id), ['720', '360', 'v1080', 'aud']);
      final best = info.formats.first;
      expect(best.sizeBytes, 1000);
      expect(best.headers, {'Referer': 'https://a/'}, reason: 'engine controls Accept-Encoding');
      expect(info.recommended!.id, '720');
      expect(info.formats[2].note, 'videoOnlyNoSound');
    });

    test('no direct formats is an error', () {
      expect(() => parseYtDlpJson(jsonEncode({'formats': []}), 'u'),
          throwsA(isA<MediaException>()));
    });
  });

  group('URL routing', () {
    test('recognizes platforms and pages', () {
      expect(MediaResolver.isYouTube(Uri.parse('https://youtu.be/abc')), isTrue);
      expect(MediaResolver.isYouTube(Uri.parse('https://m.youtube.com/watch?v=1')), isTrue);
      expect(MediaResolver.isYouTube(Uri.parse('https://notyoutube.com/')), isFalse);
      expect(MediaResolver.isReddit(Uri.parse('https://www.reddit.com/r/a/comments/1')), isTrue);
      expect(MediaResolver.isTelegram(Uri.parse('https://t.me/chan/12')), isTrue);
      expect(MediaResolver.isTelegram(Uri.parse('https://t.me/chan')), isFalse);
      expect(MediaResolver.looksLikePage(Uri.parse('https://x.test/file.zip')), isFalse);
      expect(MediaResolver.looksLikePage(Uri.parse('https://x.test/watch')), isTrue);
      expect(MediaResolver.looksLikePage(Uri.parse('https://x.test/a.html')), isTrue);
    });
  });
}
