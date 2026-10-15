import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
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

/// Tried in order; `getManifest` merges what each client returns and moves on
/// when one fails, so this doubles as our fallback chain.
final List<YoutubeApiClient> _ytClients = <YoutubeApiClient>[
  _visionOs,
  YoutubeApiClient.ios,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.androidSdkless,
  YoutubeApiClient.tv,
  YoutubeApiClient.android,
];

class Track {
  final String id;
  final String url;
  String title;
  String artist;
  String filePath;
  String? thumb;
  int durationMs;
  bool video; // saved as MP4 instead of MP3
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
/// share the link into Signal (or paste it on the Music tab), choose MP3 or
/// MP4, and the app downloads and converts it on the device. No network needed
/// afterwards.
///
/// Extraction avoids the watch page (which YouTube redirects to its /sorry/
/// rate-limit wall) and uses the VISIONOS InnerTube client. Conversion/muxing
/// is done by the bundled FFmpeg (`ffmpeg_kit_flutter_new`, GPL).
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

  /// Download (and convert) the media for a shared/pasted [url].
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
    final temps = <File>[];
    File? out;
    var durationMs = 0;

    try {
      // Streams come from the InnerTube player API only. `requireWatchPage:
      // false` keeps us off youtube.com/watch, which YouTube redirects to its
      // /sorry/ rate-limit wall far more aggressively than the API.
      final manifest =
          await _manifest(id, video: format == SaveFormat.video);

      if (format == SaveFormat.video) {
        final v = _pickVideo(manifest);
        final a = _pickAudio(manifest);
        if (v != null && a != null) {
          durationMs = _estimateMs(a);
          final vFile = File('${_dir!.path}/$id.v.${_extOf(v)}');
          temps.add(vFile);
          await _fetch(yt, v, vFile, 'Downloading video…');

          final aFile = File('${_dir!.path}/$id.a.${_extOf(a)}');
          temps.add(aFile);
          await _fetch(yt, a, aFile, 'Downloading audio…');

          out = File('${_dir!.path}/$id.mp4');
          await _run(
            '-y -i "${vFile.path}" -i "${aFile.path}" '
            '-map 0:v:0 -map 1:a:0 -c copy -movflags +faststart "${out.path}"',
            'Adding sound…',
          );
        } else if (manifest.muxed.isNotEmpty) {
          // No separate tracks — fall back to YouTube's ready-made file.
          final mux = manifest.muxed.sortByBitrate().first;
          out = File('${_dir!.path}/$id.${_extOf(mux)}');
          await _fetch(yt, mux, out, 'Downloading video…');
          durationMs = _estimateMs(mux);
        } else {
          throw const MusicException('No video stream was available for this video.');
        }
      } else {
        final a = _pickAudio(manifest);
        if (a == null) {
          throw const MusicException('No audio stream was available for this video.');
        }
        durationMs = _estimateMs(a);

        final src = File('${_dir!.path}/$id.src.${_extOf(a)}');
        await _fetch(yt, a, src, 'Downloading audio…');

        final mp3 = File('${_dir!.path}/$id.mp3');
        final ok = await _run(
          '-y -i "${src.path}" -vn -c:a libmp3lame -b:a 128k "${mp3.path}"',
          'Converting to MP3…',
          timeout: Duration(seconds: 90 + (durationMs ~/ 1000)),
        );
        if (ok && mp3.existsSync() && mp3.lengthSync() > 0) {
          out = mp3;
          try {
            src.deleteSync();
          } catch (_) {}
        } else {
          // FFmpeg unavailable/failed: keep the original audio so it still plays.
          final raw = File('${_dir!.path}/$id.${_extOf(a)}');
          try {
            src.renameSync(raw.path);
          } catch (_) {}
          out = raw.existsSync() ? raw : src;
        }
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
        video: format == SaveFormat.video,
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
      for (final f in tempFilesForCleanup(temps, out)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
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
    for (final client in _ytClients) {
      try {
        final m = await _youtube.videos.streamsClient
            .getManifest(id, ytClients: [client], requireWatchPage: false)
            .timeout(const Duration(seconds: 25));
        final hasAudio = m.audioOnly.isNotEmpty;
        final hasVideo = m.videoOnly.any((s) => s.container.name == 'mp4');
        if (video ? (hasVideo && hasAudio) : hasAudio) return m;
        if (hasAudio || m.muxed.isNotEmpty) fallback ??= m;
      } catch (e) {
        last = e;
      }
    }
    if (fallback != null) return fallback;
    throw MusicException(
        last == null ? 'Could not read this video.' : _friendly(last));
  }

  /// Streams a [stream] to [dest], reporting progress and how much has arrived.
  Future<void> _fetch(
      YoutubeExplode yt, StreamInfo stream, File dest, String label) async {
    final total = stream.size.totalBytes;
    var received = 0;
    var lastTick = 0;
    final sw = Stopwatch()..start();
    downloadingLabel = label;
    downloadProgress = total > 0 ? 0 : null;
    notifyListeners();

    final sink = dest.openWrite();
    try {
      await for (final chunk in yt.videos.streamsClient.get(stream)) {
        sink.add(chunk);
        received += chunk.length;
        final ms = sw.elapsedMilliseconds;
        // Refresh a few times a second: keeps the UI smooth and shows the
        // transfer is moving (with the MB count) on a slow connection.
        if (ms - lastTick >= 350) {
          lastTick = ms;
          downloadProgress = total > 0 ? received / total : null;
          final mb = (received / 1e6).toStringAsFixed(1);
          downloadingLabel = total > 0
              ? '$label  $mb / ${(total / 1e6).toStringAsFixed(1)} MB'
              : '$label  $mb MB';
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
  }

  /// Runs one FFmpeg command. Returns whether it succeeded.
  ///
  /// [timeout] guards against a conversion that stalls on a slow device: rather
  /// than leaving the user watching the bar forever, we cancel it and let the
  /// caller fall back to the raw stream.
  Future<bool> _run(String command, String label, {Duration? timeout}) async {
    downloadingLabel = label;
    downloadProgress = null;
    notifyListeners();
    try {
      final done = Completer<void>();
      final session = await FFmpegKit.executeAsync(command, (s) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await done.future.timeout(timeout ?? const Duration(minutes: 10));
      } on TimeoutException {
        await FFmpegKit.cancel(session.getSessionId());
        return false;
      }
      final rc = await session.getReturnCode();
      final ok = ReturnCode.isSuccess(rc);
      await FFmpegKitConfig.clearSessions();
      return ok;
    } catch (_) {
      try {
        await FFmpegKit.cancel();
      } catch (_) {}
      return false;
    }
  }

  /// The best MP4 video-only track at or below 1080p.
  ///
  /// YouTube offers 2160p/4320p for many videos, and those files are many times
  /// larger than a throttled download can pull in reasonable time (a 4K music
  /// video is ~240 MB). Capping at 1080p keeps it quick and still looks good.
  VideoOnlyStreamInfo? _pickVideo(StreamManifest m) {
    final mp4 = m.videoOnly.where((s) => s.container.name == 'mp4').toList();
    if (mp4.isEmpty) return null;
    mp4.sort((a, b) => a.videoResolution.compareTo(b.videoResolution));
    final hd = mp4.where((s) => s.videoResolution.height <= 1080).toList();
    return hd.isNotEmpty ? hd.last : mp4.first;
  }

  /// The best audio-only track, preferring AAC (MP4) for compatibility.
  AudioOnlyStreamInfo? _pickAudio(StreamManifest m) {
    final mp4 = m.audioOnly.where((s) => s.container.name == 'mp4').toList();
    final webm = m.audioOnly.where((s) => s.container.name == 'webm').toList();
    final pool = mp4.isNotEmpty ? mp4 : webm;
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
    return pool.last;
  }

  /// The on-disk extension for a stream's container.
  String _extOf(StreamInfo s) {
    final c = s.container.name;
    if (s is AudioStreamInfo) return c == 'mp4' ? 'm4a' : 'webm';
    return c; // 'mp4' or 'webm' for video/muxed
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

/// Temp files that should be removed once a download finishes, never the file
/// we are keeping.
@visibleForTesting
List<File> tempFilesForCleanup(List<File> temps, File? keep) =>
    temps.where((f) => f.path != keep?.path).toList();
