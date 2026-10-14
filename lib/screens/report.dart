import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool busy = false;
  String? narrative;
  String? err;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = st.weeklyStats();
    final delta = s.read - s.prevRead;
    final maxDay = s.perDay.fold<int>(1, (a, b) => b > a ? b : a);
    const dows = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: C.text),
        title: const Text('Weekly report',
            style: TextStyle(color: C.muted, fontSize: 15)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 60),
        children: [
          const Text('Your week',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
          const SizedBox(height: 6),
          Text(_range(), style: const TextStyle(color: C.muted)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: StatBox('Read', '${s.read}', accent: s.read > 0)),
            const SizedBox(width: 12),
            Expanded(
              child: StatBox(
                'vs last week',
                delta == 0 ? 'same' : '${delta > 0 ? '+' : ''}$delta',
                accent: delta > 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: StatBox('Streak', '${s.streak}d', accent: s.streak > 0)),
          ]),
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Items read each day',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${s.perDay[i]}',
                                style: const TextStyle(color: C.muted, fontSize: 11)),
                            const SizedBox(height: 4),
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              height: 6 + (72 * s.perDay[i] / maxDay),
                              decoration: BoxDecoration(
                                color: s.perDay[i] == 0
                                    ? const Color(0x22FFFFFF)
                                    : C.lime,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(dows[i],
                                style: const TextStyle(color: C.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _Breakdown('Top topics', s.topCategories)),
            const SizedBox(width: 12),
            Expanded(child: _Breakdown('Top sources', s.topSources)),
          ]),
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              _row('Summaries generated', '${s.summaries}'),
              _row('Items in reading list', '${s.saved}'),
              _row('Flashcards in deck', '${s.cards}'),
              _row('Cards reviewed', '${s.cardsReviewed}'),
              _row('Papers explained', '${s.papers}', last: true),
            ]),
          ),
          const SizedBox(height: 16),
          if (narrative != null) ...[
            Glass(
              olive: true,
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 16, color: C.yellow),
                  SizedBox(width: 8),
                  Text('What you learned',
                      style: TextStyle(color: C.yellow, fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                Text(narrative!, style: const TextStyle(height: 1.55, fontSize: 15)),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(err!, style: const TextStyle(color: C.yellow)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              narrative == null ? 'Summarise my week' : 'Regenerate',
              icon: Icons.auto_awesome,
              filled: narrative == null,
              busy: busy,
              onTap: () async {
                setState(() {
                  busy = true;
                  err = null;
                });
                try {
                  final text = await st.weeklyNarrative();
                  if (mounted) setState(() => narrative = text);
                } catch (e) {
                  if (mounted) setState(() => err = aiMessage(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12),
        child: Row(children: [
          Text(label, style: const TextStyle(color: C.muted)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  String _range() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final end = start.add(const Duration(days: 6));
    return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown(this.title, this.entries);
  final String title;
  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) {
    final max = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Glass(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          const Text('—', style: TextStyle(color: C.muted))
        else
          for (final e in entries) ...[
            Row(children: [
              Expanded(
                child: Text(e.key,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              Text('${e.value}', style: const TextStyle(color: C.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 5),
            ProgressBar(value: e.value / max, height: 5),
            const SizedBox(height: 9),
          ],
      ]),
    );
  }
}
