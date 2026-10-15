import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// What to save from a YouTube link.
enum SaveFormat { audio, video }

/// A user-facing failure with a message we can show as-is.
class MusicException implements Exception {
  final String message;
  const MusicException(this.message);
  @override
  String toString() => message;
}

/// The VISIONOS InnerTube client (the one yt-dlp uses): currently the most
/// reliable logged-out client. It needs no PO token and no JavaScript
/// challenge, and — unlike the default clients — it can be asked for streams
/// without fetching the watch page.
const YoutubeApiClient _visionOs = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
              '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

/// Clients tried in order. `getManifest` collects the streams from each client
/// that succeeds and only gives up once they all fail, so this doubles as the
/// fallback chain: the reliable VISIONOS client first, then others.
final List<YoutubeApiClient> _ytClients = <YoutubeApiClient>[
  _visionOs,
  YoutubeApiClient.ios,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.tv,
  YoutubeApiClient.android,
];

/// A song you saved: the audio/video lives on this device, so it plays offline.
class Track {
  final String id; // YouTube video id, also the file name
  final String url; // original link, for "Open on YouTube"
  String title;
  String artist;
  String filePath;
  String? thumb;
  int durationMs;
  bool video; // saved as MP4 instead of audio
  DateTime added;

  Track({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.filePath,
    this.thumb,
    this.durationMs = 0,
    this.video = false,
    DateTime? added,
  }) : added = added ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'artist': artist,
        'filePath': filePath,
        'thumb': thumb,
        'durationMs': durationMs,
        'video': video,
        'added': added.toIso8601String(),
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        title: (j['title'] ?? 'Untitled').toString(),
        artist: (j['artist'] ?? '').toString(),
        filePath: (j['filePath'] ?? '').toString(),
        thumb: j['thumb']?.toString(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        video: j['video'] == true,
        added: DateTime.tryParse((j['added'] ?? '').toString()),
      );
}

/// Your personal, offline library.
///
/// Music is deliberately *not* a feed. You go to YouTube, pick something and
/// share the link into Signal (or paste it on the Music tab); the app pulls
/// the media down to the device and plays it back here, with no network
/// needed afterwards.
class MusicService extends ChangeNotifier {
  final _player = AudioPlayer();
  YoutubeExplode? _yt;

  List<Track> tracks = [];
  Directory? _dir;
  bool ready = false;

  // ---- playback ----
  String? currentId;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  // ---- download ----
  bool downloading = false;
  String? downloadingLabel;
  double? downloadProgress; // 0..1, null while unknown
  String? lastError;

  bool get hasTrack => currentId != null;
  Track? get current {
    for (final t in tracks) {
      if (t.id == currentId) return t;
    }
    return null;
  }

  /// The first YouTube link inside [text], or null.
  static String? youtubeUrlIn(String text) {
    final m = RegExp(r'https?://(?:www\.|m\.|music\.)?'
            r'(?:youtube\.com/[^\s]+|youtu\.be/[^\s]+)')
        .firstMatch(text);
    if (m == null) return null;
    return m.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
  }

  /// The 11-character video id from any YouTube URL shape, or null.
  static String? youtubeId(String url) => RegExp(
          r'(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})')
      .firstMatch(url)
      ?.group(1);

  YoutubeExplode get _youtube => _yt ??= YoutubeExplode();

  Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _dir = Directory('${docs.path}/music');
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      final lib = File('${_dir!.path}/library.json');
      if (lib.existsSync()) {
        final list = jsonDecode(await lib.readAsString()) as List;
        tracks = list
            .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
            .where((t) => t.filePath.isNotEmpty && File(t.filePath).existsSync())
            .toList();
      }
    } catch (_) {
      // A broken cache should never stop the app from starting.
    }

    _player.playerStateStream.listen((s) {
      final done = s.processingState == ProcessingState.completed;
      playing = s.playing && !done;
      if (done) _onComplete();
      notifyListeners();
    });
    _player.positionStream.listen((p) {
      position = p;
      notifyListeners();
    });
    _player.durationStream.listen((d) {
      if (d != null && d > Duration.zero) duration = d;
      notifyListeners();
    });

    ready = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_dir == null) return;
    try {
      await File('${_dir!.path}/library.json')
          .writeAsString(jsonEncode(tracks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  /// True when [url] is already in the library.
  bool has(String url) {
    final id = youtubeId(url);
    return id != null && tracks.any((t) => t.id == id);
  }

  /// Video metadata from YouTube's oEmbed endpoint.
  ///
  /// This is a lightweight, stable endpoint that is *not* rate-limited the way
  /// the watch page is, so we never have to touch `youtube.com/watch` just to
  /// learn a title.
  Future<Map<String, dynamic>?> _oembed(String videoUrl) async {
    try {
      final r = await http.get(Uri.parse(
          'https://www.youtube.com/oembed?url=${Uri.encodeComponent(videoUrl)}'
          '&format=json'));
      if (r.statusCode == 200) {
        return jsonDecode(r.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Download the media for a shared/pasted [url]. Returns the new track.
  Future<Track> download(String url, {SaveFormat format = SaveFormat.audio}) async {
    final id = youtubeId(url);
    if (id == null) {
      throw const MusicException("That link doesn't look like a YouTube video.");
    }
    if (tracks.any((t) => t.id == id)) {
      throw const MusicException('That one is already in your library.');
    }
    if (_dir == null) {
      final docs = await getApplicationDocumentsDirectory();
      _dir = Directory('${docs.path}/music')..createSync(recursive: true);
    }

    downloading = true;
    downloadingLabel = 'Reading the video…';
    downloadProgress = null;
    lastError = null;
    notifyListeners();

    File? out;
    try {
      final yt = _youtube;
      final watchUrl = 'https://www.youtube.com/watch?v=$id';

      // Streams come from the InnerTube player API only. We deliberately do NOT
      // fetch the watch page: YouTube redirects those to /sorry/ (rate limit)
      // far more aggressively than it does the API.
      final manifest = await yt.videos.streamsClient.getManifest(
        id,
        ytClients: _ytClients,
        requireWatchPage: false,
      );

      late StreamInfo stream;
      late String ext;
      late bool isVideo;
      if (format == SaveFormat.video) {
        if (manifest.muxed.isEmpty) {
          throw const MusicException(
              'No video-with-sound stream was available for this one. '
              'Try saving it as audio instead.');
        }
        stream = manifest.muxed.sortByBitrate().first;
        ext = 'mp4';
        isVideo = true;
      } else {
        final aac =
            manifest.audioOnly.where((s) => s.container.name == 'mp4').toList();
        if (aac.isEmpty && manifest.audioOnly.isEmpty) {
          throw const MusicException('No audio stream was available for this video.');
        }
        stream = (aac.isNotEmpty ? aac : manifest.audioOnly).withHighestBitrate();
        ext = stream.container.name == 'mp4' ? 'm4a' : 'webm';
        isVideo = false;
      }
      out = File('${_dir!.path}/$id.$ext');

      // Metadata (title, author, thumbnail) without the watch page.
      final meta = await _oembed(watchUrl);

      downloadingLabel = isVideo ? 'Downloading video…' : 'Downloading audio…';
      notifyListeners();

      final total = stream.size.totalBytes;
      var received = 0;
      final sink = out.openWrite();
      try {
        await for (final chunk in yt.videos.streamsClient.get(stream)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            downloadProgress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      final title = (meta?['title'] ?? '').toString();
      final author = (meta?['author_name'] ?? '').toString();
      final thumb = (meta?['thumbnail_url'] ?? '').toString();
      final bps = stream.bitrate.bitsPerSecond;
      final estMs = bps > 0
          ? (stream.size.totalBytes * 8 * 1000 / bps).round()
          : 0;

      final t = Track(
        id: id,
        url: watchUrl,
        title: title.isNotEmpty ? title : 'YouTube $id',
        artist: author,
        filePath: out.path,
        thumb: thumb.isNotEmpty ? thumb : 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        durationMs: estMs,
        video: isVideo,
      );
      tracks.insert(0, t);
      await _persist();
      return t;
    } catch (e) {
      try {
        if (out != null && out.existsSync()) out.deleteSync();
      } catch (_) {}
      final msg = _friendly(e);
      lastError = msg;
      throw MusicException(msg);
    } finally {
      downloading = false;
      downloadingLabel = null;
      downloadProgress = null;
      notifyListeners();
    }
  }

  /// Turn library/network exceptions into something worth showing a person.
  String _friendly(Object e) {
    if (e is MusicException) return e.message;
    if (e is RequestLimitExceededException) {
      return 'YouTube is asking this device to slow down (rate limit). '
          'Wait a few minutes, then try again.';
    }
    if (e is VideoUnavailableException) {
      return 'That video is unavailable or private.';
    }
    if (e is VideoUnplayableException) {
      return 'That video can’t be played — it may be age- or region-restricted.';
    }
    if (e is SocketException) return 'No internet connection.';
    return 'Download failed: $e';
  }

  Future<void> delete(Track t) async {
    try {
      if (currentId == t.id) await _player.stop();
      tracks.removeWhere((x) => x.id == t.id);
      try {
        await File(t.filePath).delete();
      } catch (_) {}
      if (currentId == t.id) {
        currentId = null;
        duration = Duration.zero;
        position = Duration.zero;
      }
      await _persist();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> play(Track t) async {
    try {
      currentId = t.id;
      position = Duration.zero;
      duration = Duration(milliseconds: t.durationMs);
      playing = true;
      notifyListeners();
      await _player.setFilePath(t.filePath);
      await _player.play();
    } catch (e) {
      lastError = _friendly(e);
      playing = false;
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (currentId == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> next() async {
    if (tracks.isEmpty) return;
    final i = currentId == null ? -1 : tracks.indexWhere((t) => t.id == currentId);
    await play(tracks[(i + 1) % tracks.length]);
  }

  Future<void> previous() async {
    if (tracks.isEmpty) return;
    final i = currentId == null ? 0 : tracks.indexWhere((t) => t.id == currentId);
    await play(tracks[(i - 1 + tracks.length) % tracks.length]);
  }

  void _onComplete() {
    if (tracks.length > 1) next();
  }

  @override
  void dispose() {
    _player.dispose();
    _yt?.close();
    super.dispose();
  }
}
