import 'package:flutter_test/flutter_test.dart';
import 'package:signal_brief/screens/item.dart' show compactCount;
import 'package:signal_brief/services/music.dart';

void main() {
  group('youtube id parsing', () {
    test('handles every common link shape', () {
      const id = 'dQw4w9WgXcQ';
      expect(MusicService.youtubeId('https://www.youtube.com/watch?v=$id'), id);
      expect(MusicService.youtubeId('https://youtu.be/$id'), id);
      expect(MusicService.youtubeId('https://music.youtube.com/watch?v=$id&si=x'), id);
      expect(MusicService.youtubeId('https://www.youtube.com/shorts/$id'), id);
      expect(MusicService.youtubeId('https://www.youtube.com/embed/$id'), id);
    });

    test('rejects non-video links', () {
      expect(MusicService.youtubeId('https://example.com/hello'), isNull);
      expect(MusicService.youtubeId('not a url'), isNull);
    });
  });

  group('youtubeUrlIn', () {
    test('finds a link inside shared text', () {
      const text = 'Check this out https://youtu.be/dQw4w9WgXcQ it is great';
      expect(MusicService.youtubeUrlIn(text), 'https://youtu.be/dQw4w9WgXcQ');
    });

    test('trims trailing punctuation', () {
      expect(
        MusicService.youtubeUrlIn('song: https://youtu.be/dQw4w9WgXcQ.'),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('returns a watch link with query intact', () {
      expect(
        MusicService.youtubeUrlIn(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10'),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10',
      );
    });

    test('null when there is no youtube link', () {
      expect(MusicService.youtubeUrlIn('just some text'), isNull);
      expect(MusicService.youtubeUrlIn('https://example.com/x'), isNull);
    });
  });

  test('compactCount formats view counts', () {
    expect(compactCount(812), '812');
    expect(compactCount(15400), '15.4k');
    expect(compactCount(2300000), '2.3M');
  });

  group('saved file format', () {
    test('audio saves as m4a, video as mp4', () {
      expect(musicFileExtension(video: false), '.m4a');
      expect(musicFileExtension(video: true), '.mp4');
    });
  });

  group('visitor id', () {
    test('pulls the id out of an sw.js_data reply', () {
      const body = ")]}'\n"
          '[["yt.sw.adr",null,[[["ar","MA",null,"1.2.3.4",null,null,null,null,'
          'null,null,null,"Apple","","THE_VISITOR_ID"]]]]]';
      expect(visitorIdFromSwJsData(body), 'THE_VISITOR_ID');
    });

    test('null when the reply is not the shape we expect', () {
      expect(visitorIdFromSwJsData(''), isNull);
      expect(visitorIdFromSwJsData('not json'), isNull);
      expect(visitorIdFromSwJsData(')]}\'\n[[]]'), isNull);
    });
  });
}
