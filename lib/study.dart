import 'dart:math';

import 'models.dart';

/// How a card was recalled, mapped onto the SM-2 quality scale.
enum Review { again(1), hard(3), good(4), easy(5);
  const Review(this.quality);
  final int quality;
  String get label => switch (this) {
        Review.again => 'Again',
        Review.hard => 'Hard',
        Review.good => 'Good',
        Review.easy => 'Easy',
      };
}

/// Simplified SM-2 update. Pure function so it is easy to test.
///
/// [quality] is 0..5. Below 3 the card is considered lapsed and resets,
/// otherwise the interval grows by the card's ease factor.
Flashcard schedule(Flashcard card, int quality, [DateTime? now]) {
  final t = now ?? DateTime.now();
  var ease = card.ease;
  var reps = card.reps;
  var lapses = card.lapses;
  int interval;

  if (quality < 3) {
    reps = 0;
    lapses += 1;
    interval = 1;
    ease = max(1.3, ease - 0.2);
  } else {
    if (reps == 0) {
      interval = 1;
    } else if (reps == 1) {
      interval = 6;
    } else {
      interval = max(1, (card.intervalDays * ease).round());
    }
    reps += 1;
    ease = ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    ease = max(1.3, ease);
  }

  card
    ..ease = ease
    ..reps = reps
    ..lapses = lapses
    ..intervalDays = interval
    ..due = t.add(Duration(days: interval));
  return card;
}

/// Human label for when a card is next due.
String dueLabel(DateTime due, [DateTime? now]) {
  final t = now ?? DateTime.now();
  final diff = due.difference(t);
  if (diff.inMinutes <= 0) return 'due now';
  if (diff.inHours < 1) return 'in ${diff.inMinutes}m';
  if (diff.inHours < 24) return 'in ${diff.inHours}h';
  return 'in ${diff.inDays}d';
}
