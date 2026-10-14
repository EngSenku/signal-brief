import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key});
  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  String cat = 'All';

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final items = st.digest.where((i) => cat == 'All' || i.category == cat).toList();
    final readCount = st.digest.where((i) => st.read.contains(i.id)).length;
    final pct = st.digest.isEmpty ? 0.0 : readCount / st.digest.length;

    return RefreshIndicator(
      onRefresh: st.refresh,
      color: C.lime,
      backgroundColor: C.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Signal', style: TextStyle(color: C.muted, fontSize: 15)),
                  const Spacer(),
                  IconButton(
                    onPressed: st.loading ? null : st.refresh,
                    icon: const Icon(Icons.refresh_rounded, color: C.muted),
                  ),
                ]),
                const Text("Today's brief",
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300, height: 1.1)),
                const SizedBox(height: 6),
                Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                    style: const TextStyle(color: C.muted)),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: StatBox('Read', '$readCount / ${st.digest.length}',
                        accent: readCount > 0),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatBox(
                      'Time left',
                      st.budgetMin == 0 ? 'No limit' : '${st.minutesLeft} min',
                      accent: st.budgetMin != 0 && st.minutesLeft <= 3,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (st.digest.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ProgressBar(value: pct),
                  ),
                const SizedBox(height: 16),
                ChipRow(
                  options: kCats,
                  value: cat,
                  onChanged: (c) => setState(() => cat = c),
                ),
                if (st.loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: LinearProgressIndicator(
                        minHeight: 2, color: C.lime, backgroundColor: Color(0x1AFFFFFF)),
                  ),
                if (st.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(st.error!, style: const TextStyle(color: C.yellow)),
                  ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          if (items.isEmpty && st.loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                  child: Text('Gathering your sources…',
                      style: TextStyle(color: C.muted))),
            )
          else if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  text: st.error ??
                      'No items in this category yet. Pull down to refresh.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) => i < items.length
                      ? ItemCard(items[i], featured: i == 0 && cat == 'All')
                      : _CaughtUp(read: readCount, total: st.digest.length),
                  childCount: items.length + 1,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

class _CaughtUp extends StatelessWidget {
  const _CaughtUp({required this.read, required this.total});
  final int read, total;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Glass(
          olive: true,
          padding: const EdgeInsets.all(26),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.black),
            ),
            const SizedBox(height: 16),
            const Text("You're caught up",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300)),
            const SizedBox(height: 8),
            Text(
              'You have read $read of $total. Nothing loads below this line, so '
              'close the app and get back to work.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.muted, height: 1.4),
            ),
          ]),
        ),
      );
}
