import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../store.dart';
import '../study.dart' show Review, dueLabel;
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});
  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  int seg = 0;
  static const _labels = ['Flashcards', 'Paper', 'Goals'];

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final due = st.dueCards.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('Study',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 18),
          child: Text(
            due > 0
                ? '$due ${due == 1 ? 'card' : 'cards'} due · ${st.flashcards.length} in your deck'
                : '${st.flashcards.length} cards · nothing due right now',
            style: const TextStyle(color: C.muted),
          ),
        ),
        Glass(
          radius: 24,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            for (var i = 0; i < _labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => seg = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: seg == i ? C.lime : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(_labels[i],
                          style: TextStyle(
                            color: seg == i ? Colors.black : C.text,
                            fontWeight: FontWeight.w500,
                          )),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 18),
        if (seg == 0) const _FlashcardsTab(),
        if (seg == 1) const _PaperTab(),
        if (seg == 2) const _GoalsTab(),
      ],
    );
  }
}

// ───────────────────────── Flashcards ─────────────────────────

class _FlashcardsTab extends StatefulWidget {
  const _FlashcardsTab();
  @override
  State<_FlashcardsTab> createState() => _FlashcardsTabState();
}

class _FlashcardsTabState extends State<_FlashcardsTab> {
  final Set<String> reviewed = {};
  bool flipped = false;
  bool deckOpen = false;

  Flashcard? _current(AppState st) {
    for (final c in st.dueCards) {
      if (!reviewed.contains(c.id)) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final card = _current(st);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (st.flashcards.isEmpty)
        const EmptyState(
          icon: Icons.style_rounded,
          text: 'No flashcards yet. Open any item from the brief and tap '
              '"Flashcards" to generate a deck with AI, or add one below.',
        )
      else if (card != null)
        _ReviewCard(
          card: card,
          flipped: flipped,
          onFlip: () => setState(() => flipped = !flipped),
          onRate: (r) {
            st.reviewCard(card, r);
            setState(() {
              reviewed.add(card.id);
              flipped = false;
            });
          },
          remaining: st.dueCards.where((c) => !reviewed.contains(c.id)).length,
        )
      else
        Glass(
          olive: true,
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
              child: const Icon(Icons.done_all_rounded, color: Colors.black),
            ),
            const SizedBox(height: 14),
            const Text('Reviews done',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300)),
            const SizedBox(height: 8),
            Text(
              reviewed.isEmpty
                  ? 'Nothing is due right now. Come back when cards are scheduled.'
                  : 'You reviewed ${reviewed.length} '
                      '${reviewed.length == 1 ? 'card' : 'cards'}. Next reviews are scheduled.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: C.muted, height: 1.4),
            ),
          ]),
        ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: PillButton('Add card', icon: Icons.add_rounded,
              onTap: () => _addCardDialog(context, st)),
        ),
        const SizedBox(width: 10),
        PillButton(deckOpen ? 'Hide deck' : 'Deck (${st.flashcards.length})',
            icon: Icons.list_rounded,
            onTap: () => setState(() => deckOpen = !deckOpen)),
      ]),
      if (deckOpen) ...[
        const SizedBox(height: 16),
        _DeckList(cards: st.flashcards),
      ],
    ]);
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.card,
    required this.flipped,
    required this.onFlip,
    required this.onRate,
    required this.remaining,
  });
  final Flashcard card;
  final bool flipped;
  final VoidCallback onFlip;
  final ValueChanged<Review> onRate;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    final src = card.sourceName;
    return Column(children: [
      Row(children: [
        const Text('Review', style: TextStyle(color: C.lime, fontSize: 13)),
        if (src != null && src.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(src,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.muted, fontSize: 13)),
          ),
        ],
        const Spacer(),
        Text('$remaining left',
            style: const TextStyle(color: C.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: onFlip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          height: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: flipped ? C.lime.withValues(alpha: 0.5) : C.line),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: flipped
                  ? [C.olive1, C.olive2]
                  : [const Color(0xFF1D1E1A), const Color(0xFF121310)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(flipped ? 'ANSWER' : 'QUESTION',
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: flipped ? C.lime : C.muted)),
                const Spacer(),
                if (card.isNew)
                  const TagChip('new', color: C.yellow),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(flipped ? card.back : card.front,
                      style: const TextStyle(fontSize: 20, height: 1.4)),
                ),
              ),
              if (!flipped) ...[
                const SizedBox(height: 12),
                const Text('Tap to reveal the answer',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (!flipped)
        PillButton('Show answer', icon: Icons.visibility_rounded,
            filled: true, onTap: onFlip)
      else
        Row(children: [
          for (final r in Review.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _RateButton(r, () => onRate(r)),
              ),
            ),
        ]),
    ]);
  }
}

class _RateButton extends StatelessWidget {
  const _RateButton(this.r, this.onTap);
  final Review r;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (r) {
      Review.again => const Color(0xFFFF9E80),
      Review.hard => C.yellow,
      Review.good => C.lime,
      Review.easy => const Color(0xFF8AD9F0),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(r.label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }
}

class _DeckList extends StatelessWidget {
  const _DeckList({required this.cards});
  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 10),
        child: Text('Your deck', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ),
      for (final c in cards)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Glass(
            radius: 20,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.front,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    '${c.isNew ? 'new' : 'ease ${c.ease.toStringAsFixed(2)}'} · '
                    '${c.due.isAfter(DateTime.now()) ? 'due ${dueLabel(c.due)}' : 'due now'}',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: C.muted, size: 20),
                onPressed: () => st.deleteCard(c),
              ),
            ]),
          ),
        ),
    ]);
  }
}

void _addCardDialog(BuildContext context, AppState st) {
  final front = TextEditingController();
  final back = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('New flashcard'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(front, 'Question', maxLines: 3),
        const SizedBox(height: 10),
        _dialogField(back, 'Answer', maxLines: 4),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            if (front.text.trim().isNotEmpty && back.text.trim().isNotEmpty) {
              st.addCard(front.text, back.text);
            }
            Navigator.pop(ctx);
          },
          child: const Text('Add', style: TextStyle(color: C.lime)),
        ),
      ],
    ),
  );
}

// ───────────────────────── Paper of the week ─────────────────────────

class _PaperTab extends StatelessWidget {
  const _PaperTab();

  Item? _candidate(AppState st) {
    if (st.paperOfWeek != null) return st.paperOfWeek;
    final papers = st.trends?.papers ?? const [];
    if (papers.isNotEmpty) {
      final p = papers.first;
      return Item(
        url: p.url,
        title: p.title,
        source: 'arXiv',
        category: 'Research',
        snippet: p.subtitle,
        date: DateTime.now(),
      );
    }
    for (final i in st.digest) {
      if (i.isPaper) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final paper = _candidate(st);
    final busy = st.isBusy('paper');

    if (paper == null) {
      return const EmptyState(
        icon: Icons.science_rounded,
        text: 'No paper available yet. Refresh the brief or the Trends tab, '
            'then come back for a plain-language explanation.',
      );
    }

    final explained = st.paperExplanation != null && st.paperOfWeek?.url == paper.url;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Glass(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.science_rounded, size: 16, color: C.yellow),
            SizedBox(width: 8),
            Text('Paper of the week',
                style: TextStyle(color: C.yellow, fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          Text(paper.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, height: 1.3)),
          const SizedBox(height: 8),
          Text('${paper.source} · ${ago(paper.date)}',
              style: const TextStyle(color: C.muted, fontSize: 12)),
          if (paper.snippet.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(paper.snippet,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.muted, height: 1.45)),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: PillButton(
                explained ? 'Re-explain' : 'Explain it simply',
                icon: Icons.auto_awesome,
                filled: !explained,
                busy: busy,
                onTap: () async {
                  try {
                    await st.explainPaper(paper);
                  } catch (e) {
                    if (context.mounted) showSnack(context, aiMessage(e));
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            PillButton('Open', icon: Icons.open_in_new_rounded,
                onTap: () => openLink(paper.url)),
          ]),
        ]),
      ),
      if (explained) ...[
        const SizedBox(height: 14),
        Glass(
          olive: true,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('In plain terms',
                style: TextStyle(color: C.lime, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Text(st.paperExplanation!, style: const TextStyle(height: 1.55, fontSize: 15)),
          ]),
        ),
      ],
    ]);
  }
}

// ───────────────────────── Goals ─────────────────────────

class _GoalsTab extends StatelessWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final stats = st.weeklyStats();
    final done = st.goals.where((g) => g.done).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: StatBox('Active goals', '${st.goals.length - done}')),
        const SizedBox(width: 12),
        Expanded(
            child: StatBox('Day streak',
                '${stats.streak}', accent: stats.streak > 0)),
      ]),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton('Add a goal', icon: Icons.add_rounded,
            onTap: () => _goalDialog(context, st)),
      ),
      const SizedBox(height: 16),
      if (st.goals.isEmpty)
        const EmptyState(
          icon: Icons.flag_rounded,
          text: 'Set a learning goal — for example "Read 5 papers on diffusion" '
              'or "Review 20 flashcards this week". Tap + to progress it.',
        )
      else
        for (final g in st.goals) _GoalTile(goal: g),
    ]);
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(goal.done ? Icons.check_circle_rounded : Icons.flag_rounded,
                size: 18, color: goal.done ? C.lime : C.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(goal.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: goal.done ? TextDecoration.lineThrough : null,
                  )),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: C.muted, size: 20),
              onPressed: () => st.deleteGoal(goal),
            ),
          ]),
          const SizedBox(height: 6),
          ProgressBar(value: goal.ratio),
          const SizedBox(height: 8),
          Row(children: [
            Text('${goal.progress} / ${goal.target}',
                style: const TextStyle(color: C.muted, fontSize: 13)),
            const Spacer(),
            _RoundBtn(Icons.remove_rounded, () => st.bumpGoal(goal, -1)),
            const SizedBox(width: 8),
            _RoundBtn(Icons.add_rounded, () => st.bumpGoal(goal, 1)),
          ]),
        ]),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn(this.icon, this.onTap);
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: C.faint,
            shape: BoxShape.circle,
            border: Border.all(color: C.line),
          ),
          child: Icon(icon, size: 18, color: C.text),
        ),
      );
}

void _goalDialog(BuildContext context, AppState st) {
  final title = TextEditingController();
  final target = TextEditingController(text: '5');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('New learning goal'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(title, 'Goal, e.g. Read 5 papers on RAG'),
        const SizedBox(height: 10),
        _dialogField(target, 'Target count', keyboard: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            final t = title.text.trim();
            final n = int.tryParse(target.text.trim()) ?? 5;
            if (t.isNotEmpty) st.addGoal(t, n);
            Navigator.pop(ctx);
          },
          child: const Text('Add', style: TextStyle(color: C.lime)),
        ),
      ],
    ),
  );
}

Widget _dialogField(TextEditingController c, String hint,
        {int maxLines = 1, TextInputType? keyboard}) =>
    TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: C.muted),
        filled: true,
        fillColor: C.faint,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    );
