import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:signal_brief/screens/item.dart' show compactCount;
import 'package:signal_brief/screens/music.dart';
import 'package:signal_brief/services/music.dart';
import 'package:signal_brief/theme.dart';

/// A service with a fake document directory, so no plugin is needed.
Future<MusicService> _serviceWith(List<Track> tracks) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '/tmp/opencode/signal-brief-test',
  );
  final m = MusicService();
  await m.init();
  m.tracks.addAll(tracks);
  return m;
}

Track _song() => Track(
      id: 'dQw4w9WgXcQ',
      url: 'https://youtu.be/dQw4w9WgXcQ',
      title: 'A saved song',
      artist: 'Someone',
      filePath: '/tmp/opencode/song.m4a',
      durationMs: 184000,
    );

Track _clip() => Track(
      id: 'K0HVBm_V8w0',
      url: 'https://youtu.be/K0HVBm_V8w0',
      title: 'A saved clip',
      artist: 'Someone',
      filePath: '/tmp/opencode/clip.mp4',
      durationMs: 96000,
      video: true,
    );

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

  group('media screen', () {
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    testWidgets('lists what was saved, split into music and video',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final m = await _serviceWith([_song(), _clip()]);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: m,
        child: MaterialApp(
            theme: buildTheme(), home: const Scaffold(body: MusicScreen())),
      ));
      await tester.pump();

      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget); // the section, not the tab
      // The "Video" chip at the top and the "Video" section heading.
      expect(find.text('Video'), findsNWidgets(2));
      // Both saved items are actually on the page, once each.
      expect(find.text('A saved song'), findsOneWidget);
      expect(find.text('A saved clip'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      expect(find.text('1 video'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still names the empty half when only one kind was saved',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final m = await _serviceWith([_song()]);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: m,
        child: MaterialApp(
            theme: buildTheme(), home: const Scaffold(body: MusicScreen())),
      ));
      await tester.pump();

      expect(find.text('A saved song'), findsOneWidget);
      expect(find.text('none yet'), findsOneWidget);
      expect(find.textContaining('No videos yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });


    testWidgets('shows the empty state before anything is saved',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final m = await _serviceWith([]);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: m,
        child: MaterialApp(
            theme: buildTheme(), home: const Scaffold(body: MusicScreen())),
      ));
      await tester.pump();

      expect(find.textContaining('Nothing saved yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
