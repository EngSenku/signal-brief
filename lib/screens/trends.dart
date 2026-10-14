import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final t = st.trends;

    return RefreshIndicator(
      onRefresh: st.refreshTrends,
      color: C.lime,
      backgroundColor: C.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(children: [
              const Text('Trends',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
              const Spacer(),
              IconButton(
                onPressed: st.trendsLoading ? null : st.refreshTrends,
                icon: const Icon(Icons.refresh_rounded, color: C.muted),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 20),
            child: Text(
              t == null
                  ? 'Rising repos, models and papers this week.'
                  : 'Updated ${ago(t.fetched)}',
              style: const TextStyle(color: C.muted),
            ),
          ),
          if (st.trendsLoading && t == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator(color: C.lime)),
            )
          else if (t == null || t.isEmpty) ...[
            if (st.trendsError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(st.trendsError!,
                    style: const TextStyle(color: C.yellow)),
              ),
            const EmptyState(
              icon: Icons.trending_up_rounded,
              text: 'No trends loaded yet. Pull down to fetch the week\'s '
                  'rising repos, models and papers.',
            ),
          ] else ...[
            const _SectionHeader('Rising repositories', Icons.terminal_rounded),
            for (final e in t.repos) _TrendCard(e),
            const _SectionHeader('Trending models', Icons.memory_rounded),
            for (final e in t.models) _TrendCard(e),
            const _SectionHeader('New papers', Icons.science_rounded),
            for (final e in t.papers) _TrendCard(e, isPaper: true),
            if (st.trendsError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(st.trendsError!,
                    style: const TextStyle(color: C.yellow)),
              ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
        child: Row(children: [
          Icon(icon, size: 18, color: C.lime),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard(this.e, {this.isPaper = false});
  final TrendEntry e;
  final bool isPaper;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final saved = st.saved.any((s) => s.url == e.url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.all(16),
        onTap: () => openLink(e.url),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (e.tag.isNotEmpty) ...[
              TagChip(e.tag,
                  color: isPaper ? C.yellow : C.lime, outlined: false),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            Text(e.metric, style: const TextStyle(color: C.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(e.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 16.5, fontWeight: FontWeight.w500, height: 1.25)),
          if (e.subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.muted, height: 1.35, fontSize: 13.5)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Text(e.source, style: const TextStyle(color: C.muted, fontSize: 12)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                final item = Item(
                  url: e.url,
                  title: e.title,
                  source: e.source,
                  category: isPaper ? 'Research' : 'Dev',
                  snippet: e.subtitle,
                  date: DateTime.now(),
                );
                st.toggleSave(item);
                showSnack(context, saved ? 'Removed from reading list' : 'Saved to reading list');
              },
              child: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                size: 20,
                color: saved ? C.lime : C.muted,
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.open_in_new_rounded, size: 18, color: C.muted),
          ]),
        ]),
      ),
    );
  }
}
