import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/media/media_models.dart';
import 'package:zapdl/media/soundcloud.dart';

void main() {
  test('finds script urls and the client id', () {
    const html = '<script crossorigin src="https://a-v2.sndcdn.com/assets/0-abc.js"></script>'
        '<script src="https://example.com/x.js"></script>';
    expect(soundCloudScriptUrls(html), ['https://a-v2.sndcdn.com/assets/0-abc.js']);
    expect(soundCloudClientId('x,client_id:"AbCdEfGhIjKlMnOpQrStUvWxYz123456",y'),
        'AbCdEfGhIjKlMnOpQrStUvWxYz123456');
    expect(soundCloudClientId('nothing'), isNull);
  });

  const track = '{"kind":"track","title":"Song","duration":61000,"track_authorization":"tok",'
      '"artwork_url":"https://i1.sndcdn.com/a-large.jpg","user":{"username":"Band"},'
      '"media":{"transcodings":['
      '{"url":"https://api-v2.soundcloud.com/media/1/stream/hls","preset":"mp3_1_0",'
      '"format":{"protocol":"hls","mime_type":"audio/mpeg"}},'
      '{"url":"https://api-v2.soundcloud.com/media/1/stream/progressive","preset":"mp3_1_0",'
      '"format":{"protocol":"progressive","mime_type":"audio/mpeg"}}]}}';

  test('keeps only progressive transcodings', () {
    final t = parseSoundCloudTrack(track);
    expect(t.title, 'Song');
    expect(t.uploader, 'Band');
    expect(t.duration, const Duration(seconds: 61));
    expect(t.transcodings, hasLength(1));
    expect(t.thumbnail, contains('t500x500'));
    final info = soundCloudInfo(t, 'https://cf-media.sndcdn.com/x.mp3', 'p', 'audio/mpeg');
    expect(info.formats.single.extension, 'mp3');
    expect(info.formats.single.isAudioOnly, isTrue);
  });

  test('non-track and empty results raise clear errors', () {
    expect(() => parseSoundCloudTrack('{"kind":"playlist"}'),
        throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'unsupported')));
    expect(() => parseSoundCloudTrack('{"kind":"track","policy":"SNIP","media":{"transcodings":[]}}'),
        throwsA(isA<MediaException>().having((e) => e.reason, 'reason', 'loginRequired')));
    expect(() => parseSoundCloudTrack('oops'), throwsA(isA<MediaException>()));
  });

  test('stream url parsing', () {
    expect(parseSoundCloudStreamUrl('{"url":"https://x/y.mp3"}'), 'https://x/y.mp3');
    expect(() => parseSoundCloudStreamUrl('{}'), throwsA(isA<MediaException>()));
  });
}
