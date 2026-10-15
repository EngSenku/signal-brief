import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final m = context.watch<MusicService>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 140),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('Music',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 18),
          child: Text(
            'Your offline library. Find a song on YouTube, tap Share and pick '
            'Signal — or paste the link here. It downloads to this device.',
            style: TextStyle(color: C.muted, height: 1.4),
          ),
        ),

        // Add a track
        Glass(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add from YouTube',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Paste a link, pick a format, and it downloads here.',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 12),
            ChipRow(
              options: const ['MP3', 'MP4'],
              value: _format == SaveFormat.audio ? 'MP3' : 'MP4',
              onChanged: (v) => setState(() => _format =
                  v == 'MP4' ? SaveFormat.video : SaveFormat.audio),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _link,
              enabled: !m.downloading,
              keyboardType: TextInputType.url,
              onSubmitted: (v) => v.trim().isEmpty ? null : _add(m, v),
              decoration: InputDecoration(
                hintText: 'https://youtu.be/…',
                hintStyle: const TextStyle(color: C.muted),
                isDense: true,
                filled: true,
                fillColor: C.faint,
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
            icon: Icons.music_note_rounded,
            text: 'No songs yet. Open YouTube, find something you like, hit '
                'Share and choose Signal — it will land here, ready offline.',
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(children: [
              const Text('Your library',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${m.tracks.length} ${m.tracks.length == 1 ? 'song' : 'songs'}',
                  style: const TextStyle(color: C.muted, fontSize: 12.5)),
            ]),
          ),
          for (final t in m.tracks)
            _TrackTile(
              t: t,
              active: m.currentId == t.id,
              playing: m.playing && m.currentId == t.id,
              onTap: () => m.currentId == t.id ? m.toggle() : m.play(t),
              onDelete: () => _confirmDelete(m, t),
            ),
        ],
      ],
    );
  }
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
            _Art(t.thumb, size: 52),
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
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.delete_outline_rounded, size: 20, color: C.muted),
              ),
            ),
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
          _Art(t.thumb, size: 62),
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
              ],
            ),
          ),
        ]),
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
  const _Art(this.url, {required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: (url == null || url!.isEmpty)
              ? Container(
                  color: C.faint,
                  child: const Icon(Icons.music_note_rounded, color: C.muted))
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: C.faint,
                    child: const Icon(Icons.music_note_rounded, color: C.muted),
                  ),
                ),
        ),
      );
}
