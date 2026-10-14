import 'dart:convert';

/// A feed or data source Signal pulls from.
class Source {
  final String name, url, cat;
  final int cap, ageH;
  final double weight;

  /// Short blurb used in Settings.
  final String? about;
  const Source(this.name, this.url, this.cat,
      {this.cap = 2, this.ageH = 72, this.weight = 0, this.about});
}

/// A single digest entry / reading-list entry.
class Item {
  final String url, title, source, category, snippet;
  final DateTime? date;
  String? summary, note;

  /// Short readable intro fetched from the article, kept in memory so the
  /// "what it's about" preview only costs one request per item per session.
  /// Not persisted.
  String? preview;

  List<String> tags;

  /// True once the article body has been cached for offline reading.
  bool offline;

  /// True once the item has been turned into flashcards.
  bool carded;
  double score = 0;

  Item({
    required this.url,
    required this.title,
    required this.source,
    required this.category,
    this.snippet = '',
    this.date,
    this.summary,
    this.note,
    List<String>? tags,
    this.offline = false,
    this.carded = false,
  }) : tags = tags ?? <String>[];

  String get id => url;

  /// Research papers get a slightly different treatment in the UI.
  bool get isPaper => category == 'Research' || source == 'arXiv';

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'source': source,
        'category': category,
        'snippet': snippet,
        'date': date?.toIso8601String(),
        'summary': summary,
        'note': note,
        'tags': tags,
        'offline': offline,
        'carded': carded,
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        url: j['url'] ?? '',
        title: j['title'] ?? '',
        source: j['source'] ?? '',
        category: j['category'] ?? 'News',
        snippet: j['snippet'] ?? '',
        date: j['date'] == null ? null : DateTime.tryParse(j['date']),
        summary: j['summary'],
        note: j['note'],
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList(),
        offline: j['offline'] == true,
        carded: j['carded'] == true,
      );
}

/// A spaced-repetition flashcard, reviewed with a simplified SM-2 schedule.
class Flashcard {
  final String id;
  String front, back;
  final String? sourceUrl, sourceTitle, sourceName;
  final DateTime created;

  /// SM-2 state.
  DateTime due;
  int intervalDays; // 0 = new
  int reps;
  int lapses;
  double ease;

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.sourceUrl,
    this.sourceTitle,
    this.sourceName,
    DateTime? created,
    DateTime? due,
    this.intervalDays = 0,
    this.reps = 0,
    this.lapses = 0,
    this.ease = 2.5,
  })  : created = created ?? DateTime.now(),
        due = due ?? DateTime.now();

  bool get isNew => reps == 0 && lapses == 0;
  bool get isDue => !due.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'front': front,
        'back': back,
        'sourceUrl': sourceUrl,
        'sourceTitle': sourceTitle,
        'sourceName': sourceName,
        'created': created.toIso8601String(),
        'due': due.toIso8601String(),
        'intervalDays': intervalDays,
        'reps': reps,
        'lapses': lapses,
        'ease': ease,
      };

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: j['id'] ?? '',
        front: j['front'] ?? '',
        back: j['back'] ?? '',
        sourceUrl: j['sourceUrl'],
        sourceTitle: j['sourceTitle'],
        sourceName: j['sourceName'],
        created: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
        due: DateTime.tryParse(j['due'] ?? '') ?? DateTime.now(),
        intervalDays: j['intervalDays'] ?? 0,
        reps: j['reps'] ?? 0,
        lapses: j['lapses'] ?? 0,
        ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
      );
}

/// A learning goal, e.g. "Read 5 papers on diffusion".
class Goal {
  final String id;
  String title;
  int target;
  int progress;
  final DateTime created;

  Goal({
    required this.id,
    required this.title,
    this.target = 5,
    this.progress = 0,
    DateTime? created,
  }) : created = created ?? DateTime.now();

  bool get done => progress >= target;
  double get ratio => target == 0 ? 0 : (progress / target).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target': target,
        'progress': progress,
        'created': created.toIso8601String(),
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        target: j['target'] ?? 5,
        progress: j['progress'] ?? 0,
        created: DateTime.tryParse(j['created'] ?? '') ?? DateTime.now(),
      );
}

/// One row in the Trends tab.
class TrendEntry {
  final String title, subtitle, url, metric, source, tag;
  const TrendEntry({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.metric,
    required this.source,
    this.tag = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'url': url,
        'metric': metric,
        'source': source,
        'tag': tag,
      };

  factory TrendEntry.fromJson(Map<String, dynamic> j) => TrendEntry(
        title: j['title'] ?? '',
        subtitle: j['subtitle'] ?? '',
        url: j['url'] ?? '',
        metric: j['metric'] ?? '',
        source: j['source'] ?? '',
        tag: j['tag'] ?? '',
      );
}

/// The three lists shown in the Trends tab.
class Trends {
  final List<TrendEntry> repos, models, papers;
  final DateTime fetched;
  const Trends({
    required this.repos,
    required this.models,
    required this.papers,
    required this.fetched,
  });

  bool get isEmpty => repos.isEmpty && models.isEmpty && papers.isEmpty;

  Map<String, dynamic> toJson() => {
        'repos': repos.map((e) => e.toJson()).toList(),
        'models': models.map((e) => e.toJson()).toList(),
        'papers': papers.map((e) => e.toJson()).toList(),
        'fetched': fetched.toIso8601String(),
      };

  factory Trends.fromJson(Map<String, dynamic> j) => Trends(
        repos: _entries(j['repos']),
        models: _entries(j['models']),
        papers: _entries(j['papers']),
        fetched: DateTime.tryParse(j['fetched'] ?? '') ?? DateTime.now(),
      );

  static List<TrendEntry> _entries(dynamic raw) =>
      (raw as List?)?.map((e) => TrendEntry.fromJson(e)).toList() ?? [];
}

/// Aggregated numbers for the weekly report.
class WeeklyStats {
  final int read, prevRead, saved, summaries, cards, cardsReviewed, papers;
  final List<MapEntry<String, int>> topCategories, topSources;
  final List<int> perDay; // 7 values, oldest first
  final int streak;

  const WeeklyStats({
    required this.read,
    required this.prevRead,
    required this.saved,
    required this.summaries,
    required this.cards,
    required this.cardsReviewed,
    required this.papers,
    required this.topCategories,
    required this.topSources,
    required this.perDay,
    required this.streak,
  });
}

/// Decode a JSON string into a list, returning [] on any problem.
List<dynamic> safeDecodeList(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final v = jsonDecode(raw);
    return v is List ? v : [];
  } catch (_) {
    return [];
  }
}
