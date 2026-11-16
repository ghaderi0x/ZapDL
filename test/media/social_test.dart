import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/media/media_models.dart';
import 'package:zapdl/media/social.dart';

void main() {
  group('TikTok (tikwm)', () {
    test('offers HD, normal, watermark and sound; makes relative links absolute', () {
      final info = parseTikWm(
        jsonEncode({
          'code': 0,
          'data': {
            'title': 'Funny cat',
            'hdplay': '/video/media/hdplay/1.mp4',
            'play': 'https://cdn.example.com/p.mp4',
            'wmplay': 'https://cdn.example.com/w.mp4',
            'music': 'https://cdn.example.com/m.mp3',
            'cover': 'https://cdn.example.com/c.jpg',
            'duration': 12,
            'author': {'nickname': 'Cat Person'},
          },
        }),
        'https://www.tiktok.com/@a/video/1',
      );
      expect(info.platform, 'TikTok');
      expect(info.formats.first.url, 'https://www.tikwm.com/video/media/hdplay/1.mp4');
      expect(info.formats.map((f) => f.id), ['hd', 'sd', 'wm', 'music']);
      expect(info.uploader, 'Cat Person');
      expect(info.duration, const Duration(seconds: 12));
      expect(info.recommended!.id, 'hd');
    });

    test('slideshow gives photos; error code is not found', () {
      final info = parseTikWm(
        jsonEncode({'code': 0, 'data': {'title': 't', 'images': ['https://x/a.jpg', 'https://x/b.jpg']}}),
        'u',
      );
      expect(info.formats.where((f) => f.isImage).length, 2);
      expect(
        () => parseTikWm(jsonEncode({'code': -1, 'msg': 'Url parsing is failed'}), 'u'),
        throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'notFound')),
      );
    });
  });

  group('X (fxtwitter)', () {
    test('videos and photos', () {
      final info = parseFxTwitter(
        jsonEncode({
          'code': 200,
          'tweet': {
            'text': 'hello world',
            'author': {'name': 'Ann'},
            'media': {
              'videos': [
                {'url': 'https://video.twimg.com/a.mp4', 'height': 720, 'type': 'video'},
                {'url': 'https://video.twimg.com/g.mp4', 'type': 'gif'},
              ],
              'photos': [
                {'url': 'https://pbs.twimg.com/p.jpg'}
              ],
            },
          },
        }),
        'https://x.com/a/status/1',
      );
      expect(info.formats.length, 3);
      expect(info.formats.first.label, 'Video 1 720p');
      expect(info.formats[1].hasAudio, isFalse);
      expect(info.formats.last.isImage, isTrue);
      expect(info.uploader, 'Ann');
    });

    test('text-only tweet has nothing to download', () {
      expect(
        () => parseFxTwitter(jsonEncode({'tweet': {'text': 'hi', 'media': null}}), 'u'),
        throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'notFound')),
      );
    });
  });

  group('Instagram embed', () {
    const reel = r'{"shortcode_media":{"video_url":"https:\/\/scontent.cdninstagram.com\/v\/t50\/a.mp4?x=1&y=2",'
        r'"display_url":"https:\/\/scontent.cdninstagram.com\/cover.jpg","owner":{"username":"someone"}}}';

    test('reel: returns the video, never just the cover', () {
      final info = parseInstagramEmbed(reel, 'https://www.instagram.com/reel/abc/', expectsVideo: true);
      expect(info.formats.length, 1);
      expect(info.formats.single.isImage, isFalse);
      expect(info.formats.single.url, 'https://scontent.cdninstagram.com/v/t50/a.mp4?x=1&y=2');
      expect(info.uploader, 'someone');
    });

    test('reel without a video file asks for login instead of offering the cover', () {
      const coverOnly = r'{"display_url":"https:\/\/x\/cover.jpg"}';
      expect(
        () => parseInstagramEmbed(coverOnly, 'u', expectsVideo: true),
        throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'loginRequired')),
      );
    });

    test('photo post returns photos', () {
      const post = r'{"display_url":"https:\/\/x\/1.jpg"},{"display_url":"https:\/\/x\/2.jpg"}';
      final info = parseInstagramEmbed(post, 'u', expectsVideo: false);
      expect(info.formats.length, 2);
      expect(info.formats.every((f) => f.isImage), isTrue);
    });
  });

  group('YouTube InnerTube', () {
    test('video ids from every link form', () {
      expect(youtubeVideoId(Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1')), 'dQw4w9WgXcQ');
      expect(youtubeVideoId(Uri.parse('https://youtu.be/dQw4w9WgXcQ?si=x')), 'dQw4w9WgXcQ');
      expect(youtubeVideoId(Uri.parse('https://www.youtube.com/shorts/dQw4w9WgXcQ')), 'dQw4w9WgXcQ');
      expect(youtubeVideoId(Uri.parse('https://www.youtube.com/@channel')), isNull);
    });

    test('parses muxed + audio, skips ciphered streams, sorts by quality', () {
      final info = parseInnerTubePlayer(
        jsonEncode({
          'playabilityStatus': {'status': 'OK'},
          'videoDetails': {'title': 'T', 'author': 'A', 'lengthSeconds': '60'},
          'streamingData': {
            'formats': [
              {'itag': 18, 'url': 'https://gv/18', 'mimeType': 'video/mp4; codecs="avc1"', 'height': 360, 'contentLength': '1000'},
              {'itag': 22, 'url': 'https://gv/22', 'mimeType': 'video/mp4; codecs="avc1"', 'height': 720},
              {'itag': 99, 'signatureCipher': 's=abc', 'mimeType': 'video/mp4', 'height': 1080},
            ],
            'adaptiveFormats': [
              {'itag': 140, 'url': 'https://gv/140', 'mimeType': 'audio/mp4; codecs="mp4a"', 'bitrate': 130000},
              {'itag': 251, 'url': 'https://gv/251', 'mimeType': 'audio/webm; codecs="opus"', 'bitrate': 150000},
              {'itag': 137, 'url': 'https://gv/137', 'mimeType': 'video/mp4', 'bitrate': 9999999},
            ],
          },
        }),
        'u',
      );
      expect(info.formats.map((f) => f.id), ['m22', 'm18', 'a251', 'a140']);
      expect(info.formats.first.headers['User-Agent'], innerTubeUserAgent);
      expect(info.formats.last.extension, 'm4a');
      expect(info.duration, const Duration(seconds: 60));
    });

    test('login / unavailable statuses map to reasons', () {
      MediaException? err(String status, [String reason = '']) {
        try {
          parseInnerTubePlayer(jsonEncode({'playabilityStatus': {'status': status, 'reason': reason}}), 'u');
        } on MediaException catch (e) {
          return e;
        }
        return null;
      }

      expect(err('LOGIN_REQUIRED', 'Sign in to confirm your age')!.reason, 'loginRequired');
      expect(err('LOGIN_REQUIRED', "Sign in to confirm you're not a bot")!.reason, 'blocked');
      expect(err('ERROR', 'Video unavailable')!.reason, 'notFound');
    });
  });
}
