import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

String ago(DateTime? d) {
  if (d == null) return '';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 60) return '${m < 1 ? 1 : m}m ago';
  if (m < 1440) return '${m ~/ 60}h ago';
  return '${m ~/ 1440}d ago';
}

/// YouTube video id from any of its URL shapes, or null.
String? ytId(String url) => RegExp(
        r'(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})')
    .firstMatch(url)
    ?.group(1);

/// Thumbnail URL for a YouTube link, or null when it isn't one.
String? ytThumb(String url) {
  final id = ytId(url);
  return id == null ? null : 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}

Future<void> openLink(String url) async {
  final u = Uri.parse(url);
  try {
    if (!await launchUrl(u, mode: LaunchMode.inAppBrowserView)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }
}

/// "1.2M" / "34.5k" / "812" — for view counts and the like.
String compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String aiMessage(Object e) => e is AiException
    ? e.message
    : e.toString().replaceFirst('Exception: ', '');

void showItemSheet(BuildContext context, Item it, {bool showCards = true}) {
  context.read<AppState>().markRead(it);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AppState>(),
      child: ItemSheet(it, showCards: showCards),
    ),
  );
}

/// Compact card used in the brief, reading list, trends and study screens.
class ItemCard extends StatelessWidget {
  const ItemCard(this.it, {super.key, this.featured = false});
  final Item it;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final isRead = st.read.contains(it.id);
    final saved = st.isSaved(it);
    return Opacity(
      opacity: isRead ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Glass(
          olive: featured,
          onTap: () => showItemSheet(context, it),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(it.category,
                  style: const TextStyle(
                      color: C.lime, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(it.source,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.muted, fontSize: 13)),
              ),
              const Spacer(),
              if (it.category == 'Video' && it.views > 0) ...[
                Text('${compactCount(it.views)} views · ',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
              ],
              Text(ago(it.date), style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            if (it.category == 'Video' && ytThumb(it.url) != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    ytThumb(it.url)!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(it.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w400, height: 1.25)),
            if (it.snippet.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(it.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.muted, height: 1.35)),
            ],
            if (it.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in it.tags) TagChip(t, color: C.yellow)],
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              if (it.summary != null) ...[
                const Icon(Icons.auto_awesome, size: 14, color: C.yellow),
                const SizedBox(width: 6),
                const Text('Summarized',
                    style: TextStyle(color: C.yellow, fontSize: 12)),
              ],
              if (it.carded) ...[
                const SizedBox(width: 10),
                const Icon(Icons.style_rounded, size: 14, color: C.lime),
              ],
              if (st.hasOffline(it)) ...[
                const SizedBox(width: 10),
                const Icon(Icons.download_done_rounded, size: 14, color: C.lime),
              ],
              const Spacer(),
              GestureDetector(
                onTap: () => st.toggleSave(it),
                child: Icon(
                  saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: saved ? C.lime : C.muted,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class ItemSheet extends StatefulWidget {
  const ItemSheet(this.it, {super.key, this.showCards = true});
  final Item it;

  /// Trends cards open this sheet without the flashcard action.
  final bool showCards;
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late final TextEditingController note =
      TextEditingController(text: widget.it.note ?? '');
  String? err;
  bool offlineBusy = false;

  String? preview;
  bool aboutBusy = false;

  @override
  void initState() {
    super.initState();
    final snip = widget.it.snippet.trim();
    preview = widget.it.preview ?? (_enough(snip) ? snip : null);
    if (preview == null || preview!.isEmpty) _loadAbout();
  }

  /// True when the feed's own blurb is long enough to stand on its own.
  static bool _enough(String s) => s.length >= 180;

  Future<void> _loadAbout() async {
    final st = context.read<AppState>();
    if (mounted) setState(() => aboutBusy = true);
    final p = await st.previewFor(widget.it);
    if (!mounted) return;
    setState(() {
      preview = p.trim().isEmpty ? null : p.trim();
      aboutBusy = false;
    });
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final it = widget.it;
    final saved = st.isSaved(it);
    final busySum = st.isBusy(it.url);
    final busyCards = st.isBusy('cards:${it.url}');

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 14, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
                '${it.category} · ${it.source} · ${ago(it.date)}'
                '${it.category == 'Video' && it.views > 0 ? ' · ${compactCount(it.views)} views' : ''}',
                style: const TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 10),
            Text(it.title,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w300, height: 1.25)),
            if (it.category == 'Video' && ytThumb(it.url) != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    ytThumb(it.url)!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _about(it),
            const SizedBox(height: 18),

            // AI summary
            if (it.summary != null)
              Glass(
                olive: true,
                radius: 22,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.auto_awesome, size: 16, color: C.yellow),
                    SizedBox(width: 8),
                    Text('AI summary', style: TextStyle(color: C.yellow, fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Text(it.summary!, style: const TextStyle(height: 1.45)),
                ]),
              )
            else
              PillButton('Summarize with AI',
                  icon: Icons.auto_awesome, busy: busySum, onTap: () => _sum(st, it)),

            // Paper explanation
            if (it.isPaper) ...[
              const SizedBox(height: 12),
              if (st.paperOfWeek?.url == it.url && st.paperExplanation != null)
                Glass(
                  olive: true,
                  radius: 22,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        Icon(Icons.school_rounded, size: 16, color: C.lime),
                        SizedBox(width: 8),
                        Text('In plain terms',
                            style: TextStyle(color: C.lime, fontSize: 13)),
                      ]),
                      const SizedBox(height: 8),
                      Text(st.paperExplanation!, style: const TextStyle(height: 1.5)),
                    ],
                  ),
                )
              else
                PillButton('Explain in plain terms',
                    icon: Icons.school_rounded,
                    busy: st.isBusy('paper'),
                    onTap: () => _explain(st, it)),
            ],

            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(err!, style: const TextStyle(color: C.yellow)),
              ),
            const SizedBox(height: 18),

            // Primary actions
            Row(children: [
              Expanded(
                child: PillButton('Open', icon: Icons.open_in_new_rounded,
                    filled: true, onTap: () => openLink(it.url)),
              ),
              const SizedBox(width: 10),
              PillButton(saved ? 'Saved' : 'Save',
                  icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  onTap: () => st.toggleSave(it)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: PillButton(
                  st.hasOffline(it) ? 'Read offline' : 'Save offline',
                  icon: st.hasOffline(it)
                      ? Icons.menu_book_rounded
                      : Icons.download_rounded,
                  busy: offlineBusy,
                  onTap: () => _offline(st, it),
                ),
              ),
              if (widget.showCards) ...[
                const SizedBox(width: 10),
                PillButton('Flashcards',
                    icon: Icons.style_rounded, busy: busyCards,
                    onTap: () => _cards(st, it)),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: PillButton('Share', icon: Icons.ios_share_rounded, onTap: () {
                  SharePlus.instance.share(ShareParams(
                      text: '${it.title}\n${it.url}',
                      subject: it.title));
                }),
              ),
            ]),

            const SizedBox(height: 20),
            const Text('Tags', style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 8),
            _TagEditor(it: it, tags: it.tags, onChanged: (t) => st.setTags(it, t)),

            if (saved) ...[
              const SizedBox(height: 18),
              TextField(
                controller: note,
                maxLines: 4,
                minLines: 2,
                onChanged: (v) => st.setNote(it, v),
                decoration: InputDecoration(
                  hintText: 'Your note: what to remember or try',
                  hintStyle: const TextStyle(color: C.muted),
                  filled: true,
                  fillColor: C.faint,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The "what it's about" block: the item's own blurb, or — when that is
  /// thin — the opening of the article itself, fetched on demand.
  Widget _about(Item it) {
    final text = preview?.trim() ?? '';
    if (text.isEmpty) {
      if (!aboutBusy) return const SizedBox.shrink();
      return const Row(children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: C.muted)),
        SizedBox(width: 10),
        Text('Reading the piece…',
            style: TextStyle(color: C.muted, fontSize: 13)),
      ]);
    }
    return Glass(
      radius: 22,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
              it.category == 'Video'
                  ? Icons.play_circle_outline_rounded
                  : Icons.subject_rounded,
              size: 16,
              color: C.muted),
          const SizedBox(width: 8),
          const Text("What it's about",
              style: TextStyle(color: C.muted, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(height: 1.5)),
      ]),
    );
  }

  Future<void> _sum(AppState st, Item it) async {
    setState(() => err = null);
    try {
      await st.summarize(it);
    } catch (e) {
      if (mounted) setState(() => err = aiMessage(e));
    }
  }

  Future<void> _explain(AppState st, Item it) async {
    setState(() => err = null);
    try {
      await st.explainPaper(it);
    } catch (e) {
      if (mounted) setState(() => err = aiMessage(e));
    }
  }

  Future<void> _cards(AppState st, Item it) async {
    setState(() => err = null);
    try {
      final n = await st.makeCards(it);
      if (mounted) showSnack(context, '$n flashcards added to Study.');
    } catch (e) {
      if (mounted) setState(() => err = aiMessage(e));
    }
  }

  Future<void> _offline(AppState st, Item it) async {
    if (st.hasOffline(it)) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OfflineReader(it)));
      return;
    }
    setState(() {
      offlineBusy = true;
      err = null;
    });
    try {
      await st.saveOffline(it);
      if (mounted) {
        setState(() => offlineBusy = false);
        showSnack(context, 'Saved for offline reading.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          offlineBusy = false;
          err = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }
}

class _TagEditor extends StatefulWidget {
  const _TagEditor({required this.it, required this.tags, required this.onChanged});
  final Item it;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _add(String v) {
    final t = v.trim().toLowerCase();
    if (t.isNotEmpty && !widget.tags.contains(t)) {
      widget.onChanged([...widget.tags, t]);
    }
    c.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in widget.tags)
                    TagChip(t,
                        onDeleted: () => widget.onChanged(
                            widget.tags.where((e) => e != t).toList())),
                ],
              ),
            ),
          TextField(
            controller: c,
            onSubmitted: _add,
            decoration: InputDecoration(
              hintText: 'Add a tag, press enter',
              hintStyle: const TextStyle(color: C.muted),
              isDense: true,
              filled: true,
              fillColor: C.faint,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none),
            ),
          ),
        ],
      );
}

/// Full-screen plain-text reader for saved-offline articles.
class OfflineReader extends StatefulWidget {
  const OfflineReader(this.it, {super.key});
  final Item it;
  @override
  State<OfflineReader> createState() => _OfflineReaderState();
}

class _OfflineReaderState extends State<OfflineReader> {
  String? text;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().readOffline(widget.it).then((t) {
      if (mounted) setState(() => text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: C.text),
        title: Text(widget.it.source,
            style: const TextStyle(color: C.muted, fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: C.muted),
            onPressed: () => openLink(widget.it.url),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: C.muted),
            tooltip: 'Remove offline copy',
            onPressed: _removeOffline,
          ),
        ],
      ),
      body: text == null
          ? const Center(child: CircularProgressIndicator(color: C.lime))
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 60),
              children: [
                Text(widget.it.title,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w300, height: 1.25)),
                const SizedBox(height: 18),
                ..._blocks(text!),
                const SizedBox(height: 30),
                Text('Cached for offline reading · ${ago(widget.it.date)}',
                    style: const TextStyle(color: C.muted, fontSize: 12)),
              ],
            ),
    );
  }

  Future<void> _removeOffline() async {
    final st = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Remove offline copy?'),
        content: const Text(
            'The cached article will be deleted from this device. You can save it again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: C.lime))),
        ],
      ),
    );
    if (ok != true) return;
    await st.removeOffline(widget.it);
    if (mounted) Navigator.of(context).pop();
  }

  List<Widget> _blocks(String raw) {
    final out = <Widget>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t.substring(3),
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w500, color: C.lime)),
        ));
      } else if (t.startsWith('• ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(color: C.lime)),
            Expanded(
                child: Text(t.substring(2),
                    style: const TextStyle(height: 1.5))),
          ]),
        ));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(t, style: const TextStyle(height: 1.55, fontSize: 15.5)),
        ));
      }
    }
    return out;
  }
}
