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

/// How long to wait for another byte before calling a transfer stalled.
const Duration _stallAfter = Duration(seconds: 15);

/// How many times a stalled transfer is retried before we give up.
const int _fetchAttempts = 3;

/// YouTube accepted the request but stopped sending data.
class _StalledException implements Exception {
  const _StalledException();
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

/// Audio clients, tried in order. VISIONOS leads: it is the most reliable
/// logged-out client, needs no PO token, and can be asked for streams without
/// the watch page. `_manifest` picks the first one that answers usefully.
final List<YoutubeApiClient> _ytClients = <YoutubeApiClient>[
  _visionOs,
  YoutubeApiClient.ios,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.tv,
  YoutubeApiClient.android,
];

/// For a saved 360p video we need a client that returns YouTube's ready-made
/// *muxed* file; the Android clients do, VISIONOS/ios do not. Ordered so we hit
/// a working one immediately instead of probing the others first.
final List<YoutubeApiClient> _videoClients = <YoutubeApiClient>[
  YoutubeApiClient.androidVr,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.android,
  _visionOs,
  YoutubeApiClient.ios,
  YoutubeApiClient.tv,
];

class Track {
  final String id;
  final String url;
  String title;
  String artist;
  String filePath;
  String? thumb;
  int durationMs;
  bool video; // saved as a 360p MP4 instead of an audio (.m4a) file
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
/// share the link into Signal (or paste it on the Music tab), choose audio or
/// video, and the app saves the media on the device. No network needed after.
///
/// Nothing is re-encoded: audio is YouTube's AAC track saved as `.m4a` and
/// video is YouTube's ready-made 360p MP4 (video and audio in one file). That
/// keeps downloads small and instant and the app free of a heavy transcoder.
///
/// Extraction avoids the watch page (which YouTube redirects to its /sorry/
/// rate-limit wall) and uses the VISIONOS InnerTube client.
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
  /// A lightweight, stable endpoint that is *not* rate-limited the way the
  /// watch page is, so we never touch `youtube.com/watch` just to read a title.
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

  /// Download the media for a shared/pasted [url] into the offline library.
  ///
  /// Nothing is re-encoded: audio is YouTube's AAC stream saved as `.m4a`, and
  /// video is YouTube's ready-made 360p MP4 (video and audio in one file). Both
  /// are small and save at the network's own speed.
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

    final yt = _youtube;
    final watchUrl = 'https://www.youtube.com/watch?v=$id';
    File? out;
    var durationMs = 0;
    final video = format == SaveFormat.video;

    try {
      // Streams come from the InnerTube player API only. `requireWatchPage:
      // false` keeps us off youtube.com/watch, which YouTube redirects to its
      // /sorry/ rate-limit wall far more aggressively than the API.
      final manifest = await _manifest(id, video: video);

      final StreamInfo? stream =
          video ? _pickMuxed(manifest) : _pickAudio(manifest);
      if (stream == null) {
        throw MusicException(video
            ? 'No 360p video file was available for this link.'
            : 'No audio was available for this link.');
      }
      durationMs = _estimateMs(stream);

      out = File('${_dir!.path}/$id${musicFileExtension(video: video)}');
      await _fetch(
          yt, stream, out, video ? 'Downloading video…' : 'Downloading audio…');
      if (out.lengthSync() == 0) {
        throw const MusicException('The download came back empty. Try again.');
      }

      // Metadata (title, author, thumbnail) without the watch page.
      final meta = await _oembed(watchUrl);
      final title = (meta?['title'] ?? '').toString();
      final author = (meta?['author_name'] ?? '').toString();
      final thumb = (meta?['thumbnail_url'] ?? '').toString();

      final t = Track(
        id: id,
        url: watchUrl,
        title: title.isNotEmpty ? title : 'YouTube $id',
        artist: author,
        filePath: out.path,
        thumb: thumb.isNotEmpty ? thumb : 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
        durationMs: durationMs,
        video: video,
      );
      tracks.insert(0, t);
      await _persist();
      return t;
    } catch (e) {
      if (out != null && out.existsSync()) {
        try {
          out.deleteSync();
        } catch (_) {}
      }
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

  /// The stream manifest for [id], obtained with a single InnerTube client.
  ///
  /// Handing *every* client to `getManifest` makes the library query all of
  /// them (a player request plus a HEAD each), which is slow on a mobile
  /// connection. We stop at the first client that gives us what we need.
  Future<StreamManifest> _manifest(String id, {required bool video}) async {
    StreamManifest? fallback;
    Object? last;
    for (final client in video ? _videoClients : _ytClients) {
      try {
        final m = await _youtube.videos.streamsClient
            .getManifest(id, ytClients: [client], requireWatchPage: false)
            .timeout(const Duration(seconds: 25));
        // Video is saved as YouTube's ready-made 360p file, so we need a client
        // that returns a muxed stream; for audio the audio track is enough.
        final usable = video ? m.muxed.isNotEmpty : m.audioOnly.isNotEmpty;
        if (usable) return m;
        if (m.audioOnly.isNotEmpty || m.muxed.isNotEmpty) fallback ??= m;
      } catch (e) {
        last = e;
      }
    }
    if (fallback != null) return fallback;
    throw MusicException(
        last == null ? 'Could not read this video.' : _friendly(last));
  }

  /// Streams [stream] to [dest], reporting progress, speed and how much arrived.
  ///
  /// YouTube's media servers sometimes accept a range request and then simply
  /// stop sending — a leftover of its bitrate throttling. That used to leave the
  /// bar frozen at 0 % forever. So we watch for a dry spell, tear the request
  /// down and start again on a fresh connection, a few times before giving up
  /// with an honest message.
  Future<void> _fetch(
      YoutubeExplode yt, StreamInfo stream, File dest, String label) async {
    for (var attempt = 1;; attempt++) {
      if (attempt > 1) {
        downloadingLabel = '$label  (no data — retrying…)';
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 700));
      }
      try {
        await _pipe(yt, stream, dest, label);
        return;
      } on _StalledException {
        if (attempt >= _fetchAttempts) {
          throw const MusicException(
              'YouTube stopped sending the file. Check your connection, then '
              'try again.');
        }
      }
    }
  }

  /// One pass over the byte stream, writing to [dest].
  Future<void> _pipe(
      YoutubeExplode yt, StreamInfo stream, File dest, String label) async {
    final total = stream.size.totalBytes;
    var received = 0;
    var lastTick = 0;
    var lastBytes = 0;
    var lastAt = 0;
    final sw = Stopwatch()..start();
    downloadingLabel = label;
    downloadProgress = total > 0 ? 0 : null;
    notifyListeners();

    final sink = dest.openWrite();
    try {
      final bytes = yt.videos.streamsClient.get(stream).timeout(
        _stallAfter,
        onTimeout: (sink) {
          sink.addError(const _StalledException());
          sink.close();
        },
      );
      await for (final chunk in bytes) {
        sink.add(chunk);
        received += chunk.length;
        final ms = sw.elapsedMilliseconds;
        // Refresh a few times a second: keeps the UI smooth and shows the
        // transfer is moving — with the MB count, the live speed and an ETA —
        // even on a slow connection.
        if (ms - lastTick >= 350) {
          final bps = ms - lastAt > 0
              ? (received - lastBytes) * 1000 / (ms - lastAt)
              : 0.0;
          lastTick = ms;
          lastBytes = received;
          lastAt = ms;
          downloadProgress = total > 0 ? received / total : null;
          downloadingLabel = _progressLabel(label, received, total, bps);
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }

    if (received == 0) throw const _StalledException();
  }

  /// "Downloading audio…  3.2 / 18.4 MB · 145 KB/s · ~2 min".
  String _progressLabel(String label, int received, int total, double bytesPerSec) {
    final buf = StringBuffer(label)
      ..write('  ${(received / 1e6).toStringAsFixed(1)}');
    buf.write(total > 0
        ? ' / ${(total / 1e6).toStringAsFixed(1)} MB'
        : ' MB');
    if (bytesPerSec <= 0) return buf.toString();

    buf.write(' · ${(bytesPerSec / 1024).round()} KB/s');
    final left = total > 0 ? (total - received) / bytesPerSec : 0.0;
    if (left > 0) {
      buf.write(left < 60
          ? ' · ~${left.ceil()}s'
          : left < 3600
              ? ' · ~${(left / 60).ceil()} min'
              : ' · ~${(left / 3600).ceil()} h');
    }
    return buf.toString();
  }

  /// The smallest muxed (progressive) MP4 track, capped at 360p.
  ///
  /// YouTube serves this video *and* audio in one file, so saving it needs no
  /// muxing and no transcoder. 360p (itag 18, ~12 MB for a song-length video)
  /// keeps the download small and quick.
  MuxedStreamInfo? _pickMuxed(StreamManifest m) {
    final mp4 = m.muxed.where((s) => s.container.name == 'mp4').toList();
    if (mp4.isEmpty) return null;
    mp4.sort((a, b) => a.videoResolution.compareTo(b.videoResolution));
    final sd = mp4.where((s) => s.videoResolution.height <= 360).toList();
    return sd.isNotEmpty ? sd.last : mp4.first;
  }

  /// The best audio-only track, preferring AAC (MP4) for compatibility.
  ///
  /// `withHighestBitrate` also filters to the *default* audio track, so a video
  /// with several dubs does not hand us the wrong language.
  AudioOnlyStreamInfo? _pickAudio(StreamManifest m) {
    final mp4 = m.audioOnly.where((s) => s.container.name == 'mp4').toList();
    if (mp4.isNotEmpty) return mp4.withHighestBitrate();
    final webm = m.audioOnly.where((s) => s.container.name == 'webm').toList();
    return webm.isEmpty ? null : webm.withHighestBitrate();
  }

  /// Approximate length from stream size ÷ bitrate.
  int _estimateMs(StreamInfo s) {
    final bps = s.bitrate.bitsPerSecond;
    if (bps <= 0) return 0;
    return (s.size.totalBytes * 8 * 1000 / bps).round();
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

  Future<void> seek(Duration to) => _player.seek(to);

  Future<void> next() async {
    final list = tracks;
    if (list.length < 2) return;
    final i = list.indexWhere((t) => t.id == currentId);
    await play(list[(i + 1) % list.length]);
  }

  Future<void> previous() async {
    final list = tracks;
    if (list.length < 2) return;
    final i = list.indexWhere((t) => t.id == currentId);
    await play(list[(i - 1 + list.length) % list.length]);
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

/// The extension used for a saved item: video is `.mp4`, audio is `.m4a`.
@visibleForTesting
String musicFileExtension({required bool video}) => video ? '.mp4' : '.m4a';
