import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai.dart';
import 'article.dart';
import 'feeds.dart';
import 'models.dart';
import 'services/notifications.dart';
import 'study.dart';

const kCats = [
  'All', 'AI', 'Dev', 'Research', 'News', 'PFE', 'Video', 'Sport', 'Anime',
  'Morocco',
];

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  final _secure = const FlutterSecureStorage();
  final articleStore = ArticleStore();
  final notifications = Notifications();

  // ---- digest ----
  List<Item> digest = [];
  List<Item> saved = [];
  Set<String> read = {};
  List<String> boost = [];
  List<String> mute = [];
  Set<String> disabled = {};
  bool loading = false;
  String? error;
  DateTime? lastFetch;

  // ---- ai ----
  String nvidiaKey = kEmbeddedApiKey;
  String aiModel = kDefaultModel;
  final Set<String> _busy = {}; // item urls currently being summarized/carded

  // ---- time budget ----
  int budgetMin = 25;
  int usedSec = 0, bonusSec = 0;
  String usedDate = '';

  // ---- study ----
  List<Flashcard> flashcards = [];
  List<Goal> goals = [];

  // ---- trends ----
  Trends? trends;
  bool trendsLoading = false;
  String? trendsError;

  // ---- paper of the week ----
  Item? paperOfWeek;
  String? paperExplanation;

  // ---- offline ----
  final Set<String> offlineUrls = {};

  // ---- notifications ----
  bool notifyEnabled = false;
  int notifyHour = 8, notifyMinute = 0;

  // ---- history ----
  List<Map<String, dynamic>> history = [];

  // ---------- init ----------
  Future<void> init() async {
    _p = await SharedPreferences.getInstance();

    // API key: prefer secure storage, then prefs; otherwise fall back to the
    // key baked into the build so AI works out of the box.
    try {
      final stored = await _secure
          .read(key: 'nvidia_key')
          .timeout(const Duration(seconds: 4));
      if (stored != null && stored.isNotEmpty) {
        nvidiaKey = stored;
      } else {
        final legacy = _p.getString('nvidiaKey');
        if (legacy != null && legacy.isNotEmpty) {
          nvidiaKey = legacy;
          await _secure.write(key: 'nvidia_key', value: legacy);
          await _p.remove('nvidiaKey');
        }
      }
    } catch (_) {
      final legacy = _p.getString('nvidiaKey');
      if (legacy != null && legacy.isNotEmpty) nvidiaKey = legacy;
    }

    digest = _loadItems('digest');
    saved = _loadItems('saved');
    read = (_p.getStringList('read') ?? []).toSet();
    boost = _p.getStringList('boost') ??
        [
          'llm', 'transformer', 'pytorch', 'tensorflow', 'agent', 'rag',
          'fine-tuning', 'diffusion', 'embedding', 'quantization', 'inference',
          'gpu', 'cuda', 'dataset', 'benchmark', 'machine learning',
          'deep learning', 'data science', 'mlops', 'nlp', 'computer vision',
          'pandas', 'numpy', 'sql', 'spark', 'airflow', 'python', 'flutter',
          'rust', 'open source', 'reasoning', 'multimodal',
        ];
    mute = _p.getStringList('mute') ?? ['sponsored', 'giveaway'];
    disabled = (_p.getStringList('disabled') ?? []).toSet();
    aiModel = _p.getString('aiModel') ?? kDefaultModel;
    budgetMin = _p.getInt('budgetMin') ?? 25;
    usedSec = _p.getInt('usedSec') ?? 0;
    bonusSec = _p.getInt('bonusSec') ?? 0;
    usedDate = _p.getString('usedDate') ?? '';
    final lf = _p.getString('lastFetch');
    lastFetch = lf == null ? null : DateTime.tryParse(lf);
    offlineUrls.addAll(_p.getStringList('offlineUrls') ?? const []);
    notifyEnabled = _p.getBool('notifyEnabled') ?? false;
    notifyHour = _p.getInt('notifyHour') ?? 8;
    notifyMinute = _p.getInt('notifyMinute') ?? 0;
    history = _loadHistory();
    flashcards = _loadCards();
    goals = _loadGoals();
    final t = _p.getString('trends');
    if (t != null) {
      try {
        trends = Trends.fromJson(jsonDecode(t));
      } catch (_) {}
    }
    final pw = _p.getString('paperItem');
    if (pw != null) {
      try {
        paperOfWeek = Item.fromJson(jsonDecode(pw));
      } catch (_) {}
    }
    paperExplanation = _p.getString('paperExplanation');
    _rollDay();

    await notifications.init().timeout(const Duration(seconds: 6), onTimeout: () {});
    if (notifyEnabled) {
      await notifications
          .scheduleDaily(TimeOfDay(hour: notifyHour, minute: notifyMinute))
          .timeout(const Duration(seconds: 4), onTimeout: () {});
    }
    notifyListeners();
  }

  // ---------- persistence helpers ----------
  List<Item> _loadItems(String k) {
    final raw = _p.getString(k);
    return safeDecodeList(raw).map((e) => Item.fromJson(e)).toList();
  }

  List<Flashcard> _loadCards() =>
      safeDecodeList(_p.getString('flashcards')).map((e) => Flashcard.fromJson(e)).toList();

  List<Goal> _loadGoals() =>
      safeDecodeList(_p.getString('goals')).map((e) => Goal.fromJson(e)).toList();

  List<Map<String, dynamic>> _loadHistory() {
    final raw = _p.getString('history');
    return safeDecodeList(raw).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _saveItems() {
    _p.setString('digest', jsonEncode(digest.map((e) => e.toJson()).toList()));
    _p.setString('saved', jsonEncode(saved.map((e) => e.toJson()).toList()));
  }

  void _saveCards() =>
      _p.setString('flashcards', jsonEncode(flashcards.map((e) => e.toJson()).toList()));

  void _saveGoals() =>
      _p.setString('goals', jsonEncode(goals.map((e) => e.toJson()).toList()));

  void _saveHistory() {
    if (history.length > 2000) {
      history = history.sublist(history.length - 2000);
    }
    _p.setString('history', jsonEncode(history));
  }

  void _log(String kind, {String cat = '', String source = '', String title = ''}) {
    history.add({
      't': DateTime.now().toIso8601String(),
      'k': kind,
      'c': cat,
      's': source,
      'n': title.length > 160 ? title.substring(0, 160) : title,
    });
    _saveHistory();
  }

  // ---------- time budget ----------
  String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  void _rollDay() {
    if (usedDate != _today()) {
      usedDate = _today();
      usedSec = 0;
      bonusSec = 0;
    }
  }

  int get limitSec => budgetMin * 60 + bonusSec;
  bool get locked => budgetMin > 0 && usedSec >= limitSec;
  int get minutesLeft =>
      budgetMin == 0 ? 0 : max(0, ((limitSec - usedSec) / 60).ceil());

  void tick() {
    _rollDay();
    usedSec++;
    if (usedSec % 15 == 0 || usedSec == limitSec) {
      persistUsage();
      notifyListeners();
    }
  }

  void persistUsage() {
    _p.setInt('usedSec', usedSec);
    _p.setInt('bonusSec', bonusSec);
    _p.setString('usedDate', usedDate);
  }

  void extend() {
    bonusSec += 300;
    persistUsage();
    notifyListeners();
  }

  void setBudget(int m) {
    budgetMin = m;
    _p.setInt('budgetMin', m);
    notifyListeners();
  }

  // ---------- digest ----------
  Future<void> refreshIfStale() async {
    if (digest.isEmpty ||
        lastFetch == null ||
        DateTime.now().difference(lastFetch!).inHours >= 2) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final active = kSources.where((s) => !disabled.contains(s.name)).toList();
      final results = await fetchAllSources(active);
      final now = DateTime.now();
      final seen = <String>{};
      final picked = <Item>[];

      for (var i = 0; i < active.length; i++) {
        final s = active[i];
        final isVideo = s.cat == 'Video';
        final scored = <Item>[];
        for (final it in results[i]) {
          final hrs =
              it.date == null ? 24.0 : max(0, now.difference(it.date!).inHours).toDouble();
          // Video is the one exception to freshness: a genuinely popular older
          // upload can beat a brand-new, dull one.
          if (!isVideo && hrs > s.ageH) continue;
          final hay = '${it.title} ${it.snippet}'.toLowerCase();
          if (mute.any((m) => hay.contains(m.toLowerCase()))) continue;
          var sc = s.weight + 6 / (1 + hrs / 24);
          if (isVideo && it.views > 0) {
            // Rank by popularity (log scale) plus a gentle recency nudge.
            sc = s.weight + 2.4 * (log(it.views + 1) / ln10) + 1.5 / (1 + hrs / 336);
          }
          sc += min(3, boost.where((b) => hay.contains(b.toLowerCase())).length) * 2.5;
          it.score = sc;
          scored.add(it);
        }
        scored.sort((a, b) => b.score.compareTo(a.score));
        // Videos get a wider net so the most-watched recent upload wins.
        final cap = isVideo ? max(s.cap, 3) : s.cap;
        for (final it in scored.take(cap)) {
          if (seen.contains(it.url) || seen.contains(it.title.toLowerCase())) continue;
          seen..add(it.url)..add(it.title.toLowerCase());
          picked.add(it);
        }
      }
      picked.sort((a, b) => b.score.compareTo(a.score));

      if (picked.isEmpty) {
        error = digest.isEmpty
            ? 'No sources responded. Check your connection and try again.'
            : 'Could not refresh right now. Showing your last digest.';
      } else {
        // Build the brief with a deliberate shape: plenty from a data/AI
        // engineer's core, plus a slice of the rest of life.
        final byCat = <String, List<Item>>{};
        for (final it in picked) {
          (byCat[it.category] ??= <Item>[]).add(it);
        }
        const quota = <String, int>{
          'AI': 8, 'Dev': 5, 'Research': 4, 'News': 5, 'PFE': 4,
          'Video': 4, 'Morocco': 3, 'Sport': 2, 'Anime': 2,
        };
        const total = 36;
        final chosen = <Item>[];
        final used = <String>{};
        for (final e in quota.entries) {
          final list = byCat[e.key] ?? const <Item>[];
          for (var k = 0; k < e.value && k < list.length; k++) {
            if (used.add(list[k].url)) chosen.add(list[k]);
          }
        }
        for (final it in picked) {
          if (chosen.length >= total) break;
          if (used.add(it.url)) chosen.add(it);
        }
        chosen.sort((a, b) => b.score.compareTo(a.score));

        final old = {
          for (final d in digest) d.url: (d.summary, d.note, d.tags, d.offline, d.carded)
        };
        digest = chosen;
        for (final d in digest) {
          final prev = old[d.url];
          if (prev != null) {
            d.summary = prev.$1;
            d.note = prev.$2;
            d.tags = prev.$3;
            d.offline = prev.$4;
            d.carded = prev.$5;
          }
        }
        lastFetch = now;
        _p.setString('lastFetch', now.toIso8601String());
        if (read.length > 600) read.clear();
        _saveItems();
      }
    } catch (e) {
      error = 'Refresh failed: $e';
    }
    loading = false;
    notifyListeners();
  }

  // ---------- trends ----------
  Future<void> refreshTrendsIfStale() async {
    if (trends == null ||
        DateTime.now().difference(trends!.fetched).inHours >= 6) {
      await refreshTrends();
    }
  }

  Future<void> refreshTrends() async {
    if (trendsLoading) return;
    trendsLoading = true;
    trendsError = null;
    notifyListeners();
    try {
      final t = await fetchTrends();
      if (t.isEmpty) {
        trendsError = 'Could not load trends. Pull to retry.';
      } else {
        trends = t;
        _p.setString('trends', jsonEncode(t.toJson()));
      }
    } catch (e) {
      trendsError = 'Trends failed: $e';
    }
    trendsLoading = false;
    notifyListeners();
  }

  // ---------- reading list ----------
  bool isSaved(Item it) => saved.any((s) => s.url == it.url);

  void toggleSave(Item it) {
    if (isSaved(it)) {
      saved.removeWhere((s) => s.url == it.url);
    } else {
      saved.insert(0, it);
      _log('save', cat: it.category, source: it.source, title: it.title);
    }
    _saveItems();
    notifyListeners();
  }

  void setNote(Item it, String text) {
    it.note = text.trim().isEmpty ? null : text.trim();
    for (final s in saved) {
      if (s.url == it.url) s.note = it.note;
    }
    _saveItems();
  }

  void setTags(Item it, List<String> tags) {
    it.tags = tags;
    for (final s in saved) {
      if (s.url == it.url) s.tags = tags;
    }
    _saveItems();
    notifyListeners();
  }

  void markRead(Item it) {
    if (read.add(it.id)) {
      _p.setStringList('read', read.toList());
      _log('read', cat: it.category, source: it.source, title: it.title);
      notifyListeners();
    }
  }

  // ---------- offline ----------
  bool hasOffline(Item it) => offlineUrls.contains(it.url);

  Future<void> saveOffline(Item it) async {
    final text = await articleStore.fetchAndSave(it.url);
    if (text.isEmpty) throw Exception('Nothing readable found.');
    offlineUrls.add(it.url);
    it.offline = true;
    for (final s in saved) {
      if (s.url == it.url) s.offline = true;
    }
    _p.setStringList('offlineUrls', offlineUrls.toList());
    _saveItems();
    notifyListeners();
  }

  Future<void> removeOffline(Item it) async {
    await articleStore.delete(it.url);
    offlineUrls.remove(it.url);
    it.offline = false;
    for (final s in saved) {
      if (s.url == it.url) s.offline = false;
    }
    _p.setStringList('offlineUrls', offlineUrls.toList());
    _saveItems();
    notifyListeners();
  }

  Future<String?> readOffline(Item it) => articleStore.read(it.url);

  // ---------- settings ----------
  void setList(String key, List<String> v) {
    if (key == 'boost') boost = v;
    if (key == 'mute') mute = v;
    _p.setStringList(key, v);
    notifyListeners();
  }

  void toggleSource(String name) {
    disabled.contains(name) ? disabled.remove(name) : disabled.add(name);
    _p.setStringList('disabled', disabled.toList());
    notifyListeners();
  }

  Future<void> setKey(String k) async {
    nvidiaKey = k.trim();
    try {
      if (nvidiaKey.isEmpty) {
        await _secure.delete(key: 'nvidia_key');
      } else {
        await _secure.write(key: 'nvidia_key', value: nvidiaKey);
      }
    } catch (_) {
      _p.setString('nvidiaKey', nvidiaKey);
    }
    notifyListeners();
  }

  void setModel(String m) {
    aiModel = m;
    _p.setString('aiModel', m);
    notifyListeners();
  }

  Future<void> setReminder(bool enabled, {TimeOfDay? time}) async {
    notifyEnabled = enabled;
    if (time != null) {
      notifyHour = time.hour;
      notifyMinute = time.minute;
    }
    _p.setBool('notifyEnabled', notifyEnabled);
    _p.setInt('notifyHour', notifyHour);
    _p.setInt('notifyMinute', notifyMinute);
    if (enabled) {
      await notifications.requestPermission();
      await notifications.scheduleDaily(TimeOfDay(hour: notifyHour, minute: notifyMinute));
    } else {
      await notifications.cancel();
    }
    notifyListeners();
  }

  TimeOfDay get notifyTime => TimeOfDay(hour: notifyHour, minute: notifyMinute);

  // ---------- share to app ----------
  /// Adds shared links/text to the reading list. Returns how many were added.
  Future<int> addShared(List<String> texts) async {
    var added = 0;
    for (final raw in texts) {
      final url = _firstUrl(raw);
      if (url == null) continue;
      if (saved.any((s) => s.url == url)) continue;
      final leftover = raw.replaceAll(url, '').trim();
      final title = (await fetchPageTitle(url)) ??
          (leftover.isEmpty ? url : leftover);
      final it = Item(
        url: url,
        title: title.length > 140 ? '${title.substring(0, 140)}…' : title,
        source: 'Shared',
        category: 'News',
      );
      saved.insert(0, it);
      _log('save', cat: 'Shared', source: 'Shared', title: it.title);
      added++;
    }
    if (added > 0) _saveItems();
    notifyListeners();
    return added;
  }

  String? _firstUrl(String text) {
    final m = RegExp(r'https?://[^\s]+').firstMatch(text);
    if (m == null) return null;
    return m.group(0)!.replaceAll(RegExp(r'[),.;]+$'), '');
  }

  // ---------- AI ----------
  NvidiaClient get _ai => NvidiaClient(apiKey: nvidiaKey, model: aiModel);

  bool isBusy(String url) => _busy.contains(url);

  Future<T> _run<T>(String key, Future<T> Function() task) async {
    _busy.add(key);
    notifyListeners();
    try {
      return await task();
    } finally {
      _busy.remove(key);
      notifyListeners();
    }
  }

  /// A short, readable intro for the "what it's about" preview: the feed's own
  /// summary when it is substantial, otherwise the first paragraphs of the
  /// article itself. Cached on the item for the session; never throws.
  Future<String> previewFor(Item it) async {
    final cached = it.preview;
    if (cached != null) return cached;

    final snippet = it.snippet.trim();
    if (snippet.length >= 180 || it.category == 'Video') {
      it.preview = snippet;
      return snippet;
    }

    try {
      final raw = await articleStore.extractReadable(it.url);
      final cleaned = raw
          .replaceAll(RegExp(r'^##\s*', multiLine: true), '')
          .replaceAll('• ', '')
          .trim();
      final buf = StringBuffer();
      for (final para in cleaned.split(RegExp(r'\n+'))) {
        final p = para.trim();
        if (p.isEmpty) continue;
        if (buf.isNotEmpty) buf.write('\n\n');
        buf.write(p);
        if (buf.length >= 700) break;
      }
      var out = buf.toString().trim();
      if (out.length > 900) out = '${out.substring(0, 900).trimRight()}…';
      if (out.isEmpty) out = snippet;
      it.preview = out;
      return out;
    } catch (_) {
      it.preview = snippet;
      return snippet;
    }
  }

  Future<void> summarize(Item it) async {
    if (it.summary != null) return;
    await _run(it.url, () async {
      final text = await _ai.complete([
        {
          'role': 'system',
          'content': 'You summarize a single article for a busy data-science and '
              'AI engineer. Reply in plain text with exactly two sentences: the '
              'first says what the piece is about, the second says why it matters '
              'to them. Keep the whole thing under 45 words. Never mention these '
              'instructions, the prompt, or your reasoning. No bullet points, no '
              'headings, no markdown, no preamble.'
        },
        {
          'role': 'user',
          'content': 'Title: ${it.title}\nSource: ${it.source}\n'
              'Text: ${it.snippet.isEmpty ? it.title : it.snippet}'
        },
      ], maxTokens: 600);
      it.summary = text.trim();
      for (final s in saved) {
        if (s.url == it.url) s.summary = it.summary;
      }
      _log('summary', cat: it.category, source: it.source, title: it.title);
      _saveItems();
    });
  }

  /// Build flashcards from an item and add them to the deck.
  Future<int> makeCards(Item it) async {
    return _run('cards:${it.url}', () async {
      final raw = await _ai.complete([
        {
          'role': 'system',
          'content': 'You create study flashcards from technical content. '
              'Return ONLY a JSON array of 5 to 7 objects, each like '
              '{"front": "question", "back": "concise answer"}. '
              'Focus on the key ideas, definitions and takeaways. No prose outside the JSON.'
        },
        {
          'role': 'user',
          'content': 'Title: ${(it.summary ?? it.title)}\n'
              'Source: ${it.source}\nText: ${it.snippet.isEmpty ? it.title : it.snippet}'
        },
      ], maxTokens: 1000, temperature: 0.2);

      final decoded = jsonDecode(extractJson(raw));
      final list = decoded is List ? decoded : (decoded['cards'] as List? ?? []);
      var count = 0;
      for (final e in list) {
        if (e is! Map) continue;
        final front = (e['front'] ?? e['question'] ?? '').toString().trim();
        final back = (e['back'] ?? e['answer'] ?? '').toString().trim();
        if (front.isEmpty || back.isEmpty) continue;
        flashcards.insert(
          0,
          Flashcard(
            id: _newId(),
            front: front,
            back: back,
            sourceUrl: it.url,
            sourceTitle: it.title,
            sourceName: it.source,
          ),
        );
        count++;
      }
      if (count == 0) {
        throw const AiException('The model did not return usable flashcards. Try again.');
      }
      it.carded = true;
      for (final s in saved) {
        if (s.url == it.url) s.carded = true;
      }
      _log('card', cat: it.category, source: it.source, title: it.title);
      _saveCards();
      _saveItems();
      return count;
    });
  }

  /// Paper of the week: plain-language explanation.
  Future<void> explainPaper(Item paper) async {
    await _run('paper', () async {
      final text = await _ai.complete([
        {
          'role': 'system',
          'content': 'You explain research papers to a smart engineer who is not a '
              'specialist. Use plain language, no markdown symbols. Start with '
              '"In plain terms:" and 2-3 sentences. Then "Why it matters:" one sentence. '
              'Then "Key ideas:" followed by 3 short numbered points. Never invent '
              'results beyond the abstract.'
        },
        {
          'role': 'user',
          'content': 'Paper: ${paper.title}\nAbstract: ${paper.snippet}'
        },
      ], maxTokens: 700, temperature: 0.4);
      paperOfWeek = paper;
      paperExplanation = text;
      _p.setString('paperItem', jsonEncode(paper.toJson()));
      _p.setString('paperExplanation', text);
      _log('paper', cat: 'Research', source: paper.source, title: paper.title);
    });
  }

  /// A short narrative for the weekly report.
  Future<String> weeklyNarrative() async {
    final s = weeklyStats();
    final titles = history
        .where((h) => h['k'] == 'read' && _inThisWeek(DateTime.tryParse(h['t'] ?? '')))
        .map((h) => h['n'] ?? '')
        .where((t) => (t as String).isNotEmpty)
        .take(12)
        .join('; ');
    return _ai.complete([
      {
        'role': 'system',
        'content': 'Write a warm, motivating 3-sentence summary of what this person '
            'read and learned this week. Plain text, no markdown. Do not invent items.'
      },
      {
        'role': 'user',
        'content': 'Read ${s.read} items (last week ${s.prevRead}). '
            'Top topics: ${s.topCategories.map((e) => e.key).join(', ')}. '
            'Flashcards reviewed: ${s.cardsReviewed}. Titles: $titles'
      },
    ], maxTokens: 300, temperature: 0.6);
  }

  // ---------- study ----------
  List<Flashcard> get dueCards {
    final now = DateTime.now();
    final d = flashcards.where((c) => !c.due.isAfter(now)).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return d;
  }

  int get newCardCount => flashcards.where((c) => c.isNew).length;

  void addCard(String front, String back, {Item? from}) {
    flashcards.insert(
      0,
      Flashcard(
        id: _newId(),
        front: front.trim(),
        back: back.trim(),
        sourceUrl: from?.url,
        sourceTitle: from?.title,
        sourceName: from?.source,
      ),
    );
    _saveCards();
    notifyListeners();
  }

  void updateCard(Flashcard c, String front, String back) {
    c.front = front.trim();
    c.back = back.trim();
    _saveCards();
    notifyListeners();
  }

  void deleteCard(Flashcard c) {
    flashcards.removeWhere((x) => x.id == c.id);
    _saveCards();
    notifyListeners();
  }

  void reviewCard(Flashcard c, Review r) {
    schedule(c, r.quality);
    _log('review', cat: 'Study', source: c.sourceName ?? '', title: c.front);
    _saveCards();
    notifyListeners();
  }

  void addGoal(String title, int target) {
    goals.insert(0, Goal(id: _newId(), title: title.trim(), target: max(1, target)));
    _saveGoals();
    notifyListeners();
  }

  void bumpGoal(Goal g, int delta) {
    g.progress = max(0, g.progress + delta);
    _saveGoals();
    notifyListeners();
  }

  void deleteGoal(Goal g) {
    goals.removeWhere((x) => x.id == g.id);
    _saveGoals();
    notifyListeners();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  // ---------- weekly report ----------
  DateTime _weekStart([DateTime? ref]) {
    final now = ref ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool _inThisWeek(DateTime? t) {
    if (t == null) return false;
    return !t.isBefore(_weekStart());
  }

  WeeklyStats weeklyStats() {
    final thisStart = _weekStart();
    final prevStart = thisStart.subtract(const Duration(days: 7));
    final cats = <String, int>{};
    final srcs = <String, int>{};
    var readThis = 0, readPrev = 0, reviews = 0, papers = 0;
    final perDay = List<int>.filled(7, 0);

    for (final h in history) {
      final t = DateTime.tryParse(h['t'] as String? ?? '');
      if (t == null) continue;
      final k = h['k'] as String? ?? '';
      if (t.isBefore(prevStart)) continue;
      final inThis = !t.isBefore(thisStart);
      if (k == 'read') {
        if (inThis) {
          readThis++;
          final c = (h['c'] ?? '').toString();
          final s = (h['s'] ?? '').toString();
          if (c.isNotEmpty) cats[c] = (cats[c] ?? 0) + 1;
          if (s.isNotEmpty) srcs[s] = (srcs[s] ?? 0) + 1;
          final idx = t.difference(thisStart).inDays;
          if (idx >= 0 && idx < 7) perDay[idx]++;
        } else {
          readPrev++;
        }
      } else if (k == 'review' && inThis) {
        reviews++;
      } else if (k == 'paper' && inThis) {
        papers++;
      }
    }

    // Streak: consecutive days ending today with at least one read.
    var streak = 0;
    final readDays = history
        .where((h) => h['k'] == 'read')
        .map((h) => DateTime.tryParse(h['t'] as String? ?? ''))
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    while (readDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    List<MapEntry<String, int>> top(Map<String, int> m) {
      final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return l.take(4).toList();
    }

    return WeeklyStats(
      read: readThis,
      prevRead: readPrev,
      saved: saved.length,
      summaries: {
        for (final i in [...digest, ...saved])
          if (i.summary != null) i.url,
      }.length,
      cards: flashcards.length,
      cardsReviewed: reviews,
      papers: papers,
      topCategories: top(cats),
      topSources: top(srcs),
      perDay: perDay,
      streak: streak,
    );
  }
}
