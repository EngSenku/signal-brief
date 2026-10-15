import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../services/music.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Your personal, offline music library.
///
/// Nothing here is a feed. Find a song on YouTube, tap Share, and pick
/// Signal — or paste the link below. The audio is saved on this device and
/// plays back here, no connection needed.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});
  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _link = TextEditingController();
  String? _err;
  SaveFormat _format = SaveFormat.audio;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _add(MusicService m, String input) async {
    final url = MusicService.youtubeUrlIn(input) ?? input.trim();
    setState(() => _err = null);
    try {
      final t = await m.download(url, format: _format);
      _link.clear();
      if (mounted) showSnack(context, 'Saved “${t.title}” for offline use.');
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _confirmDelete(MusicService m, Track t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete this?'),
        content: Text('“${t.title}” and its downloaded file will be removed '
            'from this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: C.lime))),
        ],
      ),
    );
    if (ok == true) await m.delete(t);
  }

  /// Tapping a row: a song toggles in place, a clip opens its own screen.
  Future<void> _open(MusicService m, Track t) async {
    if (!t.video) {
      m.currentId == t.id ? m.toggle() : m.play(t);
      return;
    }
    if (m.currentId != t.id) await m.play(t);
    if (!mounted) return;
    await watchVideo(context);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MusicService>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 140),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('Media',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 18),
          child: Text(
            'Your offline music and video library. Find a song or a clip on '
            'YouTube, tap Share and pick Signal — or paste the link here. It '
            'downloads to this device.',
            style: TextStyle(color: C.muted, height: 1.4),
          ),
        ),

        // Add a track
        Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add from YouTube',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text(
                'Audio saves as a .m4a (same quality as an MP3); video saves '
                'as a 360p .mp4.',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 12),
            ChipRow(
              options: const ['Audio', 'Video'],
              value: _format == SaveFormat.audio ? 'Audio' : 'Video',
              onChanged: (v) => setState(() => _format =
                  v == 'Video' ? SaveFormat.video : SaveFormat.audio),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              enabled: !m.downloading,
              keyboardType: TextInputType.url,
              onSubmitted: (v) => v.trim().isEmpty ? null : _add(m, v),
              decoration: InputDecoration(
                hintText: 'https://youtu.be/…',
                hintStyle: const TextStyle(color: C.muted),
                filled: true,
                fillColor: C.faint,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              PillButton('Download',
                  icon: Icons.download_rounded,
                  filled: true,
                  busy: m.downloading,
                  onTap: () => _link.text.trim().isEmpty
                      ? null
                      : _add(m, _link.text)),
            ]),
            if (m.downloading) ...[
              const SizedBox(height: 14),
              Text(m.downloadingLabel ?? 'Working…',
                  style: const TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 8),
              if (m.downloadProgress != null)
                ProgressBar(value: m.downloadProgress!)
              else
                const LinearProgressIndicator(
                    minHeight: 3, color: C.lime, backgroundColor: Color(0x1AFFFFFF)),
            ],
            if (_err != null || m.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_err ?? m.lastError!,
                    style: const TextStyle(color: C.yellow, height: 1.35)),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        // Now playing
        if (m.current != null) _NowPlaying(m: m),
        if (m.current != null) const SizedBox(height: 18),

        if (m.tracks.isEmpty)
          const EmptyState(
            icon: Icons.library_music_rounded,
            text: 'Nothing saved yet. Open YouTube, find a song or a video you '
                'like, hit Share and choose Signal — it will land here, ready '
                'offline.',
          )
        else
          ..._library(m),
      ],
    );
  }

  /// The library, split into its two halves.
  ///
  /// Keeping this out of the [ListView]'s children avoids the classic
  /// dangling-`else` trap of a nested `if` inside a collection literal.
  List<Widget> _library(MusicService m) {
    final songs = m.tracks.where((t) => !t.video).toList();
    final clips = m.tracks.where((t) => t.video).toList();
    return [
      _SectionHead('Music', songs.length, 'song', 'songs'),
      if (songs.isEmpty)
        const _SectionHint('No songs yet — paste a link with the Audio chip '
            'above to keep one offline.')
      else
        for (final t in songs) _tile(m, t),
      const SizedBox(height: 18),
      _SectionHead('Video', clips.length, 'video', 'videos'),
      if (clips.isEmpty)
        const _SectionHint('No videos yet — paste a link with the Video chip '
            'above to save a 360p MP4 you can watch offline.')
      else
        for (final t in clips) _tile(m, t),
    ];
  }

  Widget _tile(MusicService m, Track t) => _TrackTile(
        t: t,
        active: m.currentId == t.id,
        playing: m.playing && m.currentId == t.id,
        onTap: () => _open(m, t),
        onDelete: () => _confirmDelete(m, t),
      );
}

/// A library section title with its count, e.g. "Music  3 songs".
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.label, this.count, this.one, this.many);
  final String label;
  final int count;
  final String one, many;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(children: [
          Text(label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(
              count == 0
                  ? 'none yet'
                  : '$count ${count == 1 ? one : many}',
              style: const TextStyle(color: C.muted, fontSize: 12.5)),
        ]),
      );
}

/// The muted line shown in a section that has nothing in it yet.
class _SectionHint extends StatelessWidget {
  const _SectionHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
        child: Text(text,
            style: const TextStyle(color: C.muted, fontSize: 13, height: 1.35)),
      );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.t,
    required this.active,
    required this.playing,
    required this.onTap,
    required this.onDelete,
  });
  final Track t;
  final bool active, playing;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.all(12),
          olive: active,
          onTap: onTap,
          child: Row(children: [
            _Art(t.thumb, size: 52, video: t.video),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: active ? C.lime : C.text)),
                  const SizedBox(height: 3),
                  Text(t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: C.muted, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (t.video) ...[
              const Icon(Icons.movie_rounded, size: 14, color: C.muted),
              const SizedBox(width: 6),
            ],
            Text(_clock(Duration(milliseconds: t.durationMs)),
                style: const TextStyle(color: C.muted, fontSize: 12)),
            // Keep the delete target a good distance from the play button: a
            // thumb reaching for play must not land on delete.
            const SizedBox(width: 14),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.delete_outline_rounded, size: 20, color: C.muted),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              size: 34,
              color: active ? C.lime : C.text,
            ),
          ]),
        ),
      );
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.m});
  final MusicService m;

  @override
  Widget build(BuildContext context) {
    final t = m.current!;
    final total = m.duration.inMilliseconds > 0
        ? m.duration
        : Duration(milliseconds: t.durationMs);
    final pos = m.position > total ? total : m.position;
    return Glass(
      olive: true,
      child: Column(children: [
        Row(children: [
          _Art(t.thumb, size: 62, video: t.video),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Text(t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.muted, fontSize: 13)),
                if (t.video) ...[
                  const SizedBox(height: 5),
                  const Row(children: [
                    Icon(Icons.movie_rounded, size: 13, color: C.muted),
                    SizedBox(width: 5),
                    Text('Video · 360p',
                        style: TextStyle(color: C.muted, fontSize: 12)),
                  ]),
                ],
              ],
            ),
          ),
        ]),
        if (t.video) ...[
          const SizedBox(height: 12),
          Row(children: [
            PillButton('Watch video',
                icon: Icons.play_circle_outline_rounded,
                filled: true,
                onTap: () => watchVideo(context)),
          ]),
        ],
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: C.lime,
            thumbColor: C.lime,
            inactiveTrackColor: const Color(0x33FFFFFF),
            trackHeight: 3,
            overlayColor: Colors.transparent,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: total.inMilliseconds == 0
                ? 0
                : pos.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
            max: total.inMilliseconds == 0 ? 1 : total.inMilliseconds.toDouble(),
            onChanged: (v) => m.seek(Duration(milliseconds: v.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            Text(_clock(pos), style: const TextStyle(color: C.muted, fontSize: 12)),
            const Spacer(),
            Text(_clock(total), style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            iconSize: 34,
            color: C.text,
            onPressed: m.previous,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: m.toggle,
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
              child: Icon(m.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black, size: 32),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            iconSize: 34,
            color: C.text,
            onPressed: m.next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art(this.url, {required this.size, this.video = false});
  final String? url;
  final double size;

  /// Where the artwork is missing (offline, or a clip without a poster), a
  /// video shows a movie glyph so a saved clip never looks like a song.
  final bool video;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: (url == null || url!.isEmpty)
              ? _fallback()
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                ),
        ),
      );

  Widget _fallback() => Container(
        color: C.faint,
        child: Icon(video ? Icons.movie_rounded : Icons.music_note_rounded,
            color: C.muted),
      );
}

/// Open the full-screen player for the clip that is loaded.
Future<void> watchVideo(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const _VideoPage()));

/// Full-screen playback for a saved clip, with picture.
class _VideoPage extends StatelessWidget {
  const _VideoPage();

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MusicService>();
    final t = m.current;
    final c = m.videoController;
    final total = m.duration.inMilliseconds > 0
        ? m.duration
        : Duration(milliseconds: t?.durationMs ?? 0);
    final pos = m.position > total ? total : m.position;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              color: Colors.white,
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded),
            ),
            Expanded(
              child: Text(t?.title ?? 'Video',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w500)),
            ),
          ]),
          Expanded(
            child: Center(
              child: (c == null || !c.value.isInitialized)
                  ? const Icon(Icons.movie_rounded, size: 46, color: C.muted)
                  : AspectRatio(
                      aspectRatio: c.value.aspectRatio,
                      child: VideoPlayer(c),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
            child: Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: C.lime,
                  thumbColor: C.lime,
                  inactiveTrackColor: const Color(0x33FFFFFF),
                  trackHeight: 3,
                  overlayColor: Colors.transparent,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: total.inMilliseconds == 0
                      ? 0
                      : pos.inMilliseconds
                          .clamp(0, total.inMilliseconds)
                          .toDouble(),
                  max: total.inMilliseconds == 0
                      ? 1
                      : total.inMilliseconds.toDouble(),
                  onChanged: (v) => m.seek(Duration(milliseconds: v.round())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Text(_clock(pos),
                      style: const TextStyle(color: C.muted, fontSize: 12)),
                  const Spacer(),
                  Text(_clock(total),
                      style: const TextStyle(color: C.muted, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  iconSize: 34,
                  color: Colors.white,
                  onPressed: m.previous,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: m.toggle,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: const BoxDecoration(
                        color: C.lime, shape: BoxShape.circle),
                    child: Icon(
                        m.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 34),
                  ),
                ),
                const SizedBox(width: 18),
                IconButton(
                  iconSize: 34,
                  color: Colors.white,
                  onPressed: m.next,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
