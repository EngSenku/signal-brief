import 'package:flutter_test/flutter_test.dart';
import 'package:signal_brief/models.dart';
import 'package:signal_brief/study.dart';

void main() {
  group('SM-2 scheduling', () {
    test('a new card rated Good comes back in 1 day, then 6', () {
      final c = Flashcard(id: '1', front: 'q', back: 'a');
      final t = DateTime(2026, 1, 1);

      schedule(c, Review.good.quality, t);
      expect(c.reps, 1);
      expect(c.intervalDays, 1);
      expect(c.due, t.add(const Duration(days: 1)));

      schedule(c, Review.good.quality, t);
      expect(c.reps, 2);
      expect(c.intervalDays, 6);
    });

    test('a lapsed card resets and records a lapse', () {
      final c = Flashcard(id: '1', front: 'q', back: 'a');
      final t = DateTime(2026, 1, 1);
      schedule(c, Review.good.quality, t);
      schedule(c, Review.good.quality, t);
      expect(c.reps, 2);

      schedule(c, Review.again.quality, t);
      expect(c.reps, 0);
      expect(c.lapses, 1);
      expect(c.intervalDays, 1);
    });

    test('ease never drops below 1.3', () {
      final c = Flashcard(id: '1', front: 'q', back: 'a');
      final t = DateTime(2026, 1, 1);
      for (var i = 0; i < 20; i++) {
        schedule(c, Review.again.quality, t);
      }
      expect(c.ease, greaterThanOrEqualTo(1.3));
    });

    test('easy cards grow faster than good cards', () {
      final good = Flashcard(id: 'a', front: 'q', back: 'a');
      final easy = Flashcard(id: 'b', front: 'q', back: 'a');
      final t = DateTime(2026, 1, 1);
      for (var i = 0; i < 3; i++) {
        schedule(good, Review.good.quality, t);
        schedule(easy, Review.easy.quality, t);
      }
      expect(easy.ease, greaterThan(good.ease));
      expect(easy.intervalDays, greaterThanOrEqualTo(good.intervalDays));
    });
  });

  group('models round-trip', () {
    test('Item preserves tags, notes, offline and carded flags', () {
      final it = Item(
        url: 'https://x.test/a',
        title: 'Hello',
        source: 'arXiv',
        category: 'Research',
        snippet: 'abstract',
        date: DateTime(2026, 2, 2),
        tags: ['rag', 'llm'],
        offline: true,
        carded: true,
      )..note = 'remember this';
      final back = Item.fromJson(it.toJson());
      expect(back.url, it.url);
      expect(back.tags, ['rag', 'llm']);
      expect(back.offline, isTrue);
      expect(back.carded, isTrue);
      expect(back.note, 'remember this');
      expect(back.isPaper, isTrue);
    });

    test('Flashcard survives serialisation', () {
      final c = Flashcard(
        id: '42',
        front: 'q',
        back: 'a',
        sourceUrl: 'https://x',
        sourceTitle: 'T',
        sourceName: 'S',
        ease: 2.7,
        reps: 3,
        intervalDays: 15,
      );
      final back = Flashcard.fromJson(c.toJson());
      expect(back.id, '42');
      expect(back.ease, 2.7);
      expect(back.reps, 3);
      expect(back.intervalDays, 15);
      expect(back.sourceName, 'S');
    });

    test('Goal progress and ratio', () {
      final g = Goal(id: 'g', title: 'Read papers', target: 4, progress: 2);
      expect(g.ratio, 0.5);
      expect(g.done, isFalse);
      g.progress = 4;
      expect(g.done, isTrue);
      expect(Goal.fromJson(g.toJson()).target, 4);
    });

    test('Trends round-trips entries', () {
      final t = Trends(
        repos: const [
          TrendEntry(
              title: 'a/b',
              subtitle: 's',
              url: 'u',
              metric: '★ 1k',
              source: 'GitHub',
              tag: 'Python'),
        ],
        models: const [],
        papers: const [],
        fetched: DateTime(2026, 3, 3),
      );
      final back = Trends.fromJson(t.toJson());
      expect(back.repos.single.title, 'a/b');
      expect(back.repos.single.tag, 'Python');
      expect(back.models, isEmpty);
    });
  });

  group('safeDecodeList', () {
    test('handles null, junk and valid input', () {
      expect(safeDecodeList(null), isEmpty);
      expect(safeDecodeList('not json'), isEmpty);
      expect(safeDecodeList('[1,2,3]'), [1, 2, 3]);
      expect(safeDecodeList('{"a":1}'), isEmpty);
    });
  });

  group('dueLabel', () {
    test('describes near and far dates', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(dueLabel(now.subtract(const Duration(minutes: 5)), now), 'due now');
      expect(dueLabel(now.add(const Duration(minutes: 30)), now), 'in 30m');
      expect(dueLabel(now.add(const Duration(hours: 5)), now), 'in 5h');
      expect(dueLabel(now.add(const Duration(days: 3)), now), 'in 3d');
    });
  });
}
