import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  String query = '';
  String? tagFilter;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final allTags = <String>{
      for (final i in st.saved) ...i.tags,
    }.toList()
      ..sort();

    final q = query.trim().toLowerCase();
    final items = st.saved.where((i) {
      if (tagFilter != null && !i.tags.contains(tagFilter)) return false;
      if (q.isEmpty) return true;
      return i.title.toLowerCase().contains(q) ||
          i.snippet.toLowerCase().contains(q) ||
          i.source.toLowerCase().contains(q) ||
          (i.note ?? '').toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('Reading list',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 16),
          child: Text(
            '${st.saved.length} saved · ${st.saved.where((i) => i.offline).length} offline',
            style: const TextStyle(color: C.muted),
          ),
        ),
        if (st.saved.isNotEmpty) ...[
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: 'Search your reading list',
              hintStyle: const TextStyle(color: C.muted),
              prefixIcon: const Icon(Icons.search_rounded, color: C.muted),
              filled: true,
              fillColor: C.faint,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
            ),
          ),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GestureDetector(
                  onTap: () => setState(() => tagFilter = null),
                  child: TagChip('All',
                      color: tagFilter == null ? C.lime : C.muted,
                      outlined: tagFilter != null),
                ),
                for (final t in allTags)
                  GestureDetector(
                    onTap: () =>
                        setState(() => tagFilter = tagFilter == t ? null : t),
                    child: TagChip(t,
                        color: tagFilter == t ? C.lime : C.yellow,
                        outlined: tagFilter != t),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
        if (st.saved.isEmpty)
          const EmptyState(
            icon: Icons.bookmark_border_rounded,
            text: 'Nothing saved yet. Tap the bookmark on anything worth '
                'studying later, or share a link into Signal from another app.',
          )
        else if (items.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            text: 'No saved items match that search or tag.',
          )
        else
          for (final it in items) _SavedTile(it),
      ],
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile(this.it);
  final Item it;

  @override
  Widget build(BuildContext context) => Column(children: [
        ItemCard(it),
        if (it.note != null && it.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Note: ${it.note}',
                  style: const TextStyle(color: C.yellow, height: 1.35)),
            ),
          ),
      ]);
}
