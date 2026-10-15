import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A song you saved: the audio lives on this device, so it plays offline.
class Track {
  final String id; // YouTube video id, also the file name
  final String url; // original link, for "Open on YouTube"
  String title;
  String artist;
  String filePath;
  String? thumb;
  int durationMs;
  DateTime added;

  Track({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.filePath,
    this.thumb,
    this.durationMs = 0,
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
        added: DateTime.tryParse((j['added'] ?? '').toString()),
      );
}

/// Your personal, offline music library.
///
/// Music is deliberately *not* a feed. You go to YouTube, pick a song and
/// share the link into Signal (or paste it on the Music screen); the app
/// pulls just the audio track down to the device and plays it back here,
/// with no network needed afterwards.
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

  /// Download the audio for a shared/pasted [url]. Returns the new track.
  Future<Track> download(String url) async {
    final id = youtubeId(url);
    if (id == null) {
      throw 'That link doesn\'t look like a YouTube video.';
    }
    if (tracks.any((t) => t.id == id)) {
      throw 'That song is already in your library.';
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
      final video = await yt.videos.get(id);
      final manifest = await yt.videos.streamsClient.getManifest(id);
      if (manifest.audioOnly.isEmpty) {
        throw 'No audio stream was available for this video.';
      }
      // Prefer AAC in MP4 (m4a): the most widely supported container for
      // playback. Fall back to whatever exists (usually Opus/WebM).
      final m4a =
          manifest.audioOnly.where((s) => s.container.name == 'mp4').toList();
      final audio = (m4a.isNotEmpty ? m4a : manifest.audioOnly)
          .withHighestBitrate();
      final ext = audio.container.name == 'mp4' ? 'm4a' : 'webm';
      out = File('${_dir!.path}/$id.$ext');

      downloadingLabel = 'Downloading audio…';
      notifyListeners();

      final total = audio.size.totalBytes;
      var received = 0;
      final sink = out.openWrite();
      try {
        await for (final chunk in yt.videos.streamsClient.get(audio)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            downloadProgress = (received / total).clamp(0.0, 1.0);
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      final music = video.musicData.isNotEmpty ? video.musicData.first : null;
      final t = Track(
        id: id,
        url: 'https://www.youtube.com/watch?v=$id',
        title: (music?.song?.trim().isNotEmpty ?? false)
            ? music!.song!.trim()
            : video.title,
        artist: (music?.artist?.trim().isNotEmpty ?? false)
            ? music!.artist!.trim()
            : video.author,
        filePath: out.path,
        thumb: music?.image?.toString() ?? video.thumbnails.highResUrl,
        durationMs: video.duration?.inMilliseconds ?? 0,
      );
      tracks.insert(0, t);
      await _persist();
      return t;
    } catch (e) {
      // Don't leave a half-written file behind.
      try {
        if (out != null && out.existsSync()) out.deleteSync();
      } catch (_) {}
      lastError = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      downloading = false;
      downloadingLabel = null;
      downloadProgress = null;
      notifyListeners();
    }
  }

  Future<void> delete(Track t) async {
    if (currentId == t.id) await _player.stop();
    tracks.removeWhere((x) => x.id == t.id);
    try {
      final f = File(t.filePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await _persist();
    if (currentId == t.id) {
      currentId = null;
      playing = false;
      position = Duration.zero;
      duration = Duration.zero;
    }
    notifyListeners();
  }

  Future<void> play(Track t) async {
    try {
      currentId = t.id;
      position = Duration.zero;
      duration = Duration(milliseconds: t.durationMs);
      notifyListeners();
      await _player.setFilePath(t.filePath);
      await _player.play();
    } catch (e) {
      lastError = e.toString().replaceFirst('Exception: ', '');
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

  Future<void> next() => _step(1);
  Future<void> previous() => _step(-1);

  Future<void> _step(int delta) async {
    if (tracks.isEmpty) return;
    final i = tracks.indexWhere((t) => t.id == currentId);
    final n = ((i < 0 ? 0 : i) + delta) % tracks.length;
    await play(tracks[(n + tracks.length) % tracks.length]);
  }

  void _onComplete() {
    // Roll into the next track, if there is one.
    if (tracks.length > 1) next();
  }

  @override
  void dispose() {
    _player.dispose();
    _yt?.close();
    super.dispose();
  }
}
