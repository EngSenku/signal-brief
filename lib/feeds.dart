import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_rss/dart_rss.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// A browser-like user agent. Several publishers (Reddit, YouTube, Google
/// News, many CDNs) reject generic clients, so we look like a normal reader.
const kUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

/// The active sources behind the daily brief — the well-known, high-volume
/// feeds across a data/AI engineer's world *and* the rest of life: tech news,
/// world news, science, sport, anime and Morocco / PFE opportunities.
const kSources = <Source>[
  // ---------------------------------------------------------------- AI / ML
  Source('Hugging Face', 'https://huggingface.co/blog/feed.xml', 'AI',
      cap: 2, ageH: 168, weight: 2, about: 'Models, datasets and open ML news.'),
  Source('OpenAI', 'https://openai.com/news/rss.xml', 'AI',
      cap: 1, ageH: 240, weight: 2),
  Source('Google DeepMind', 'https://deepmind.google/blog/rss.xml', 'AI',
      cap: 1, ageH: 240, weight: 2),
  Source('Google Research', 'https://research.google/blog/rss/', 'AI',
      cap: 1, ageH: 240, weight: 1),
  Source('Google AI', 'https://blog.google/technology/ai/rss/', 'AI',
      cap: 1, ageH: 168),
  Source('NVIDIA', 'https://blogs.nvidia.com/feed/', 'AI', cap: 1, ageH: 168),
  Source('Microsoft Research', 'https://www.microsoft.com/en-us/research/feed/',
      'AI', cap: 1, ageH: 240),
  Source('Berkeley BAIR', 'https://bair.berkeley.edu/blog/feed.xml', 'AI',
      cap: 1, ageH: 336),
  Source('The Gradient', 'https://thegradient.pub/rss/', 'AI',
      cap: 1, ageH: 336),
  Source("Lil'Log", 'https://lilianweng.github.io/index.xml', 'AI',
      cap: 1, ageH: 720, about: 'Lilian Weng on deep learning.'),
  Source('Sebastian Raschka', 'https://magazine.sebastianraschka.com/feed',
      'AI', cap: 1, ageH: 336),
  Source('Towards Data Science', 'https://towardsdatascience.com/feed', 'AI',
      cap: 2, ageH: 72),
  Source('KDnuggets', 'https://www.kdnuggets.com/feed', 'AI',
      cap: 2, ageH: 96),
  Source('MarkTechPost', 'https://www.marktechpost.com/feed/', 'AI',
      cap: 2, ageH: 72),
  Source('Machine Learning Mastery', 'https://machinelearningmastery.com/feed/',
      'AI', cap: 1, ageH: 240),
  Source('PyTorch', 'https://pytorch.org/blog/feed.xml', 'AI',
      cap: 1, ageH: 336),
  Source('Qwen', 'https://qwenlm.github.io/blog/index.xml', 'AI',
      cap: 1, ageH: 336),
  Source('SemiAnalysis', 'https://semianalysis.com/feed/', 'AI',
      cap: 1, ageH: 336, about: 'Deep analysis of AI hardware and chips.'),
  Source('ByteByteGo', 'https://blog.bytebytego.com/feed', 'AI',
      cap: 1, ageH: 240),
  Source('Import AI', 'https://importai.substack.com/feed', 'AI',
      cap: 1, ageH: 336, about: "Jack Clark's weekly AI roundup."),
  Source('r/MachineLearning',
      'https://www.reddit.com/r/MachineLearning/top/.rss?t=day', 'AI',
      cap: 2, ageH: 48),
  Source('r/LocalLLaMA', 'https://www.reddit.com/r/LocalLLaMA/top/.rss?t=day',
      'AI', cap: 2, ageH: 48, about: 'Open models and local inference.'),
  Source('r/datascience', 'https://www.reddit.com/r/datascience/top/.rss?t=day',
      'AI', cap: 2, ageH: 48),
  Source('r/deeplearning',
      'https://www.reddit.com/r/deeplearning/top/.rss?t=week', 'AI',
      cap: 1, ageH: 96),

  // ------------------------------------------------------- Dev / engineering
  Source('Hacker News', 'https://hnrss.org/frontpage?points=150', 'Dev',
      cap: 3, ageH: 48, about: 'Top technical links as they get traction.'),
  Source('Hacker News (best)', 'https://hnrss.org/best', 'Dev',
      cap: 2, ageH: 72),
  Source('Lobsters', 'https://lobste.rs/rss', 'Dev',
      cap: 2, ageH: 48, about: 'Smaller, higher-signal dev community.'),
  Source('GitHub Trending',
      'https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml', 'Dev',
      cap: 2, ageH: 48, about: 'Repos gaining stars today.'),
  Source('GitHub Blog', 'https://github.blog/feed/', 'Dev', cap: 1, ageH: 168),
  Source('Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index',
      'Dev', cap: 2, ageH: 48),
  Source('Simon Willison', 'https://simonwillison.net/atom/everything/', 'Dev',
      cap: 2, ageH: 120, about: 'Practical AI and Python notes.'),
  Source('InfoQ', 'https://feed.infoq.com/', 'Dev', cap: 1, ageH: 120),
  Source('The New Stack', 'https://thenewstack.io/feed/', 'Dev',
      cap: 1, ageH: 96),
  Source('Google Developers', 'https://developers.googleblog.com/feed/', 'Dev',
      cap: 1, ageH: 168),
  Source('Real Python', 'https://realpython.com/atom.xml', 'Dev',
      cap: 2, ageH: 168),
  Source('Go Blog', 'https://go.dev/blog/feed.atom', 'Dev', cap: 1, ageH: 336),
  Source('Rust Blog', 'https://blog.rust-lang.org/feed.xml', 'Dev',
      cap: 1, ageH: 336),
  Source('Cloudflare Blog', 'https://blog.cloudflare.com/rss/', 'Dev',
      cap: 1, ageH: 168),
  Source('Netflix Tech Blog', 'https://netflixtechblog.com/feed', 'Dev',
      cap: 1, ageH: 336),
  Source('Martin Fowler', 'https://martinfowler.com/feed.atom', 'Dev',
      cap: 1, ageH: 336),
  Source('Julia Evans', 'https://jvns.ca/atom.xml', 'Dev', cap: 1, ageH: 336),
  Source('Dan Luu', 'https://danluu.com/atom.xml', 'Dev', cap: 1, ageH: 336),
  Source('Stack Overflow Blog', 'https://stackoverflow.blog/feed/', 'Dev',
      cap: 1, ageH: 240),
  Source('Smashing Magazine', 'https://www.smashingmagazine.com/feed/', 'Dev',
      cap: 1, ageH: 168),
  Source('The New Stack', 'https://thenewstack.io/feed/', 'Dev',
      cap: 1, ageH: 168),
  Source('InfoQ (feed)', 'https://feed.infoq.com/tags/ai-ml-data-eng/', 'Dev',
      cap: 1, ageH: 240),
  Source('r/programming', 'https://www.reddit.com/r/programming/top/.rss?t=day',
      'Dev', cap: 2, ageH: 48),
  Source('r/FlutterDev', 'https://www.reddit.com/r/flutterdev/top/.rss?t=week',
      'Dev', cap: 1, ageH: 96),

  // ------------------------------------------------------- Research / science
  Source('arXiv', 'https://rss.arxiv.org/rss/cs.LG+cs.AI+cs.CL+cs.CV', 'Research',
      cap: 5, ageH: 96, weight: 1, about: 'New machine-learning papers.'),
  Source('Nature', 'https://www.nature.com/nature.rss', 'Research',
      cap: 2, ageH: 96),
  Source('Quanta', 'https://api.quantamagazine.org/feed/', 'Research',
      cap: 2, ageH: 336, about: 'Beautiful math and science stories.'),
  Source('Phys.org', 'https://phys.org/rss-feed/', 'Research',
      cap: 2, ageH: 48),
  Source('ScienceDaily', 'https://www.sciencedaily.com/rss/all.xml', 'Research',
      cap: 2, ageH: 48),
  Source('New Scientist', 'https://www.newscientist.com/feed/home/', 'Research',
      cap: 2, ageH: 48),
  Source('Space.com', 'https://www.space.com/feeds/all', 'Research',
      cap: 1, ageH: 72),
  Source('NASA', 'https://www.nasa.gov/rss/dyn/breaking_news.rss', 'Research',
      cap: 1, ageH: 168),

  // ------------------------------------------------------------------- News
  Source('BBC News', 'https://feeds.bbci.co.uk/news/rss.xml', 'News',
      cap: 2, ageH: 36),
  Source('BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml', 'News',
      cap: 2, ageH: 36),
  Source('CNN', 'http://rss.cnn.com/rss/cnn_topstories.rss', 'News',
      cap: 2, ageH: 36),
  Source('The Guardian', 'https://www.theguardian.com/world/rss', 'News',
      cap: 2, ageH: 36),
  Source('NYT World', 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml',
      'News', cap: 2, ageH: 36),
  Source('NPR', 'https://feeds.npr.org/1001/rss.xml', 'News',
      cap: 2, ageH: 48),
  Source('Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml', 'News',
      cap: 1, ageH: 36),
  Source('DW', 'https://rss.dw.com/rdf/rss-en-all', 'News',
      cap: 1, ageH: 48),
  Source('France 24', 'https://www.france24.com/en/rss', 'News',
      cap: 1, ageH: 48),
  Source('Euronews', 'https://www.euronews.com/rss?level=theme&name=news',
      'News', cap: 1, ageH: 48),
  Source('Politico', 'https://rss.politico.com/politics-news.xml', 'News',
      cap: 1, ageH: 48),
  Source('Time', 'https://time.com/feed/', 'News', cap: 1, ageH: 72),
  Source('TechCrunch', 'https://techcrunch.com/feed/', 'News',
      cap: 2, ageH: 48),
  Source('The Verge', 'https://www.theverge.com/rss/index.xml', 'News',
      cap: 1, ageH: 48),
  Source('Wired', 'https://www.wired.com/feed/rss', 'News',
      cap: 1, ageH: 72),
  Source('MIT Tech Review', 'https://www.technologyreview.com/feed/', 'News',
      cap: 1, ageH: 96),
  Source('Ars Technica (tech)', 'https://feeds.arstechnica.com/arstechnica/tech',
      'News', cap: 1, ageH: 48),
  Source('Bloomberg', 'https://feeds.bloomberg.com/markets/news.rss', 'News',
      cap: 1, ageH: 48, about: 'Markets and business.'),
  Source('CNBC', 'https://www.cnbc.com/id/100003114/device/rss/rss.html',
      'News', cap: 1, ageH: 48),
  Source('MarketWatch', 'https://feeds.marketwatch.com/marketwatch/topstories/',
      'News', cap: 1, ageH: 48),
  Source('Google News',
      'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en', 'News',
      cap: 3, ageH: 24, about: 'Top stories, aggregated.'),

  // ------------------------------------------------------------------ Video
  Source('Andrej Karpathy',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCXUPKJO5MZQN11PqgIvyuvQ',
      'Video', cap: 1, ageH: 720, weight: 3),
  Source('Yannic Kilcher',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCZHmQk67mSJgfCCTn7xBfew',
      'Video', cap: 1, ageH: 480),
  Source('Two Minute Papers',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg',
      'Video', cap: 1, ageH: 480),
  Source('Machine Learning Street Talk',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCMLtBahI5DMrt0NPvDSoIRQ',
      'Video', cap: 1, ageH: 720),
  Source('Lex Fridman',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCSHZKyawb77ixDdsGog4iWA',
      'Video', cap: 1, ageH: 720),
  Source('AI Explained',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCNJ1Ymd5yFuUPtn21xtRbbw',
      'Video', cap: 1, ageH: 480),
  Source('Matthew Berman',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCawZsQWqfGSbCI5yjkdVkTA',
      'Video', cap: 1, ageH: 480),
  Source('Sam Witteveen',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC55ODQSvARtgSyc8ThfiepQ',
      'Video', cap: 1, ageH: 480),
  Source('Krish Naik',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCNU_lfiiWBdtULKOw6X0Dig',
      'Video', cap: 1, ageH: 480),
  Source('codebasics',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCh9nVJoWXmFb7sLApWGcLPQ',
      'Video', cap: 1, ageH: 480),
  Source('StatQuest',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCtYLUTtgS3k1Fg4y5tAhLbw',
      'Video', cap: 1, ageH: 480, about: 'Stats and ML, explained simply.'),
  Source('sentdex',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCfzlCWGWYyIQ0aLC5w48gBQ',
      'Video', cap: 1, ageH: 480),
  Source('Data School',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCnVzApLJE2ljPZSeQylSEyg',
      'Video', cap: 1, ageH: 480),
  Source('Rob Mulla',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCxladMszXan-jfgzyeIMyvw',
      'Video', cap: 1, ageH: 480),
  Source('Tina Huang',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC2UXDak6o7rBm23k3Vv5dww',
      'Video', cap: 1, ageH: 480),
  Source('Weights & Biases',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCBp3w4DCEC64FZr4k9ROxig',
      'Video', cap: 1, ageH: 720),
  Source('DeepLearning.AI',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCcIXc5mJsHVYTZR1maL5l9w',
      'Video', cap: 1, ageH: 480),
  Source('IBM Technology',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCKWaEZ-_VweaEx1j62do_vQ',
      'Video', cap: 1, ageH: 480),
  Source('NVIDIA Developer',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCBHcMCGaiJhv-ESTcWGJPcw',
      'Video', cap: 1, ageH: 480),
  Source('OpenAI (video)',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCXZCJLdBC09xxGZ6gcdrc6A',
      'Video', cap: 1, ageH: 720),
  Source('Google DeepMind (video)',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCP7jMXSY2xbc3KCAE0MHQ-A',
      'Video', cap: 1, ageH: 720),
  Source('3Blue1Brown',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw',
      'Video', cap: 1, ageH: 720),
  Source('Veritasium',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCHnyfMqiRRG1u-2MsSQLbXA',
      'Video', cap: 1, ageH: 720),
  Source('Kurzgesagt',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCsXVk37bltHxD1rDPwtNM8Q',
      'Video', cap: 1, ageH: 720),
  Source('Fireship',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA',
      'Video', cap: 1, ageH: 480),
  Source('Computerphile',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC9-y-6csu5WGm29I7JiwpnA',
      'Video', cap: 1, ageH: 720),

  // ------------------------------------------------------------------ Sport
  Source('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml', 'Sport',
      cap: 2, ageH: 48),
  Source('BBC Football', 'https://feeds.bbci.co.uk/sport/football/rss.xml',
      'Sport', cap: 1, ageH: 48),
  Source('The Guardian Sport', 'https://www.theguardian.com/sport/rss', 'Sport',
      cap: 1, ageH: 48),
  Source('The Guardian Football', 'https://www.theguardian.com/football/rss',
      'Sport', cap: 1, ageH: 48),
  Source('Sky Sports', 'https://www.skysports.com/rss/12040', 'Sport',
      cap: 1, ageH: 48),
  Source('Motorsport', 'https://www.motorsport.com/rss/all/news/', 'Sport',
      cap: 1, ageH: 72),
  Source('Marca (EN)', 'https://e00-marca.uecdn.es/rss/en/index.xml', 'Sport',
      cap: 1, ageH: 48),
  Source('Formula 1',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCB_qr75-ydFVKSF9Dmo6izg',
      'Sport', cap: 1, ageH: 336),
  Source('ESPN',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCiWLfSweyRNmLpgEHekhoAg',
      'Sport', cap: 1, ageH: 336),

  // ------------------------------------------------------------------ Anime
  Source('Anime News Network', 'https://www.animenewsnetwork.com/all/rss.xml',
      'Anime', cap: 2, ageH: 96),
  Source('MyAnimeList News', 'https://myanimelist.net/rss/news.xml', 'Anime',
      cap: 2, ageH: 96),
  Source('Anime Corner', 'https://animecorner.me/feed/', 'Anime',
      cap: 2, ageH: 96),
  Source('Otaku USA', 'https://otakuusamagazine.com/feed/', 'Anime',
      cap: 1, ageH: 168),
  Source('Anime UK News', 'https://animeuknews.net/feed/', 'Anime',
      cap: 1, ageH: 168),
  Source('Crunchyroll',
      'https://feeds.feedburner.com/crunchyroll/rss/anime', 'Anime',
      cap: 2, ageH: 96),
  Source('Anime Herald', 'https://www.animeherald.com/feed/', 'Anime',
      cap: 1, ageH: 168),
  Source('r/anime', 'https://www.reddit.com/r/anime/top/.rss?t=day', 'Anime',
      cap: 1, ageH: 48),

  // -------------------------------------------------- Morocco / PFE / jobs
  Source('Morocco — PFE', 'https://news.google.com/rss/search?q=PFE+Maroc&hl=fr&gl=MA&ceid=MA:fr',
      'Morocco', cap: 3, ageH: 168, weight: 2,
      about: 'Final-year project (PFE) news in Morocco.'),
  Source('Morocco — stages & PFE',
      'https://news.google.com/rss/search?q=stage+PFE+informatique&hl=fr&gl=MA&ceid=MA:fr',
      'Morocco', cap: 3, ageH: 168, weight: 2,
      about: 'Internships and PFE placements.'),
  Source('Morocco — emplois IT',
      'https://news.google.com/rss/search?q=Maroc+emploi+informatique&hl=fr&gl=MA&ceid=MA:fr',
      'Morocco', cap: 2, ageH: 168),
  Source('Morocco — data & IA',
      'https://news.google.com/rss/search?q=Maroc+data+science+emploi+OR+intelligence+artificielle&hl=fr&gl=MA&ceid=MA:fr',
      'Morocco', cap: 2, ageH: 168),
  Source('Morocco — startups & tech',
      'https://news.google.com/rss/search?q=Morocco+startup+OR+technology&hl=en-US&gl=US&ceid=US:en',
      'Morocco', cap: 2, ageH: 168),
  Source('Morocco — AI',
      'https://news.google.com/rss/search?q=Morocco+artificial+intelligence&hl=en-US&gl=US&ceid=US:en',
      'Morocco', cap: 2, ageH: 168),
  Source('Morocco — top news',
      'https://news.google.com/rss?hl=fr&gl=MA&ceid=MA:fr', 'Morocco',
      cap: 2, ageH: 72),
  Source('r/Morocco', 'https://www.reddit.com/r/Morocco/top/.rss?t=week',
      'Morocco', cap: 2, ageH: 168,
      about: 'Moroccan community discussions.'),
];

/// Fetch every source, but gently: most run in parallel, Reddit and the other
/// rate-limited hosts go one at a time so we don't get 429s.
Future<List<List<Item>>> fetchAllSources(List<Source> sources) async {
  final results = List<List<Item>>.generate(sources.length, (_) => const []);

  final slow = <int>[]; // rate-limited hosts, fetched sequentially
  final fast = <int>[];
  for (var i = 0; i < sources.length; i++) {
    final host = Uri.tryParse(sources[i].url)?.host ?? '';
    if (host.contains('reddit.com')) {
      slow.add(i);
    } else {
      fast.add(i);
    }
  }

  var next = 0;
  Future<void> lane() async {
    while (true) {
      final index = next < fast.length ? fast[next++] : -1;
      if (index < 0) return;
      results[index] = await fetchSource(sources[index]);
    }
  }

  await Future.wait(List.generate(8, (_) => lane()));

  for (final index in slow) {
    results[index] = await fetchSource(sources[index]);
    await Future.delayed(const Duration(milliseconds: 1200));
  }

  return results;
}

/// Fetch and normalise a single RSS/Atom source.
Future<List<Item>> fetchSource(Source s) async {
  try {
    final r = await http
        .get(Uri.parse(s.url), headers: {
          'User-Agent': kUserAgent,
          'Accept':
              'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
          'Accept-Language': 'en-US,en;q=0.9,fr;q=0.8',
        })
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return [];
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final out = <Item>[];

    // YouTube puts the real blurb in <media:description>, not <description>.
    final videoDescs = RegExp(r'<media:description>([\s\S]*?)</media:description>')
        .allMatches(body)
        .map((m) => cleanText(m.group(1)))
        .toList();
    final isGoogleNews = s.url.contains('news.google.com');

    if (RegExp(r'<feed[\s>]').hasMatch(body)) {
      final f = AtomFeed.parse(body);
      for (var i = 0; i < f.items.length; i++) {
        final e = f.items[i];
        final url = e.links.isNotEmpty ? (e.links.first.href ?? '') : '';
        final title = cleanText(e.title);
        if (url.isEmpty || title.isEmpty) continue;
        out.add(Item(
          url: url.trim(),
          title: title,
          source: s.name,
          category: s.cat,
          snippet: s.cat == 'Video'
              ? (i < videoDescs.length ? videoDescs[i] : '')
              : cleanText(e.summary ?? e.content),
          date: parseDate(e.published ?? e.updated),
        ));
      }
    } else {
      final f = RssFeed.parse(body);
      for (final e in f.items) {
        final url = e.link ?? '';
        final title = cleanText(e.title);
        if (url.isEmpty || title.isEmpty) continue;
        out.add(Item(
          url: url.trim(),
          title: isGoogleNews ? _stripPublisher(title) : title,
          source: s.name,
          category: s.cat,
          snippet: isGoogleNews ? '' : cleanText(e.description),
          date: parseDate(e.pubDate?.toString()),
        ));
      }
    }
    return out;
  } catch (_) {
    return [];
  }
}

/// Google News titles look like "Headline - Publisher"; drop the suffix.
String _stripPublisher(String title) {
  final m = RegExp(r'^(.*?)\s+-\s+[^-]{2,40}$').firstMatch(title);
  return m != null ? m.group(1)!.trim() : title;
}

/// Strip HTML and tidy up feed snippets.
String cleanText(String? s) {
  if (s == null) return '';
  var t = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  t = t
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#8217;', "'")
      .replaceAll('&#8216;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#8230;', '…')
      .replaceAll('&hellip;', '…');
  final a = t.indexOf('Abstract:');
  if (a >= 0) t = t.substring(a + 9);
  if (t.contains('Comments URL')) return '';
  t = t
      .replaceAll(RegExp(r'submitted by.*', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'The post .*? appeared first on .*?\.',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'Continue reading.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'Read more.*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[…\]|\[\.\.\.\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.length > 400 ? t.substring(0, 400).trimRight() : t;
}

/// Parse the many date formats feeds use into a DateTime.
DateTime? parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final direct = DateTime.tryParse(s);
  if (direct != null) return direct;
  try {
    return HttpDate.parse(s);
  } catch (_) {}

  // e.g. "Mon, 02 Jan 2006 15:04:05 +0000" or "02 Jan 2006 15:04:05 +0100"
  final m = RegExp(
          r'(?:[A-Za-z]{3},?\s+)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?(?:\s*([+-]\d{4}))?')
      .firstMatch(s);
  if (m == null) return null;
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final month = months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var d = DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final z = m.group(7);
  if (z != null) {
    final sign = z[0] == '-' ? -1 : 1;
    final offsetMin = sign *
        (int.parse(z.substring(1, 3)) * 60 + int.parse(z.substring(3, 5)));
    d = d.subtract(Duration(minutes: offsetMin));
  }
  return d;
}

/// Fetch the three "rising this week" lists for the Trends tab.
Future<Trends> fetchTrends() async {
  final results = await Future.wait([
    _fetchTrendingRepos(),
    _fetchTrendingModels(),
    _fetchRecentPapers(),
  ]);
  return Trends(
    repos: results[0],
    models: results[1],
    papers: results[2],
    fetched: DateTime.now(),
  );
}

Future<List<TrendEntry>> _fetchTrendingRepos() async {
  try {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final d = '${since.year}-${since.month.toString().padLeft(2, '0')}-'
        '${since.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
        'https://api.github.com/search/repositories?q=created:>$d&sort=stars&order=desc&per_page=15');
    final r = await http.get(uri, headers: {
      'User-Agent': kUserAgent,
      'Accept': 'application/vnd.github+json',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final items = (j['items'] as List?) ?? [];
    return items.map((e) {
      final stars = e['stargazers_count'] ?? 0;
      final lang = (e['language'] ?? '').toString();
      return TrendEntry(
        title: (e['full_name'] ?? '').toString(),
        subtitle: cleanText((e['description'] ?? '').toString()),
        url: (e['html_url'] ?? '').toString(),
        metric: '★ ${_compact(stars)}',
        source: 'GitHub',
        tag: lang,
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

Future<List<TrendEntry>> _fetchTrendingModels() async {
  try {
    final uri = Uri.parse(
        'https://huggingface.co/api/models?sort=trendingScore&direction=-1&limit=15');
    final r = await http
        .get(uri, headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    return list.map((e) {
      final downloads = e['downloads'] ?? 0;
      return TrendEntry(
        title: (e['modelId'] ?? e['id'] ?? '').toString(),
        subtitle: (e['pipeline_tag'] ?? '').toString(),
        url: 'https://huggingface.co/${e['modelId'] ?? e['id']}',
        metric: '${_compact(downloads)} dl',
        source: 'Hugging Face',
        tag: (e['pipeline_tag'] ?? '').toString(),
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

Future<List<TrendEntry>> _fetchRecentPapers() async {
  try {
    final uri = Uri.parse(
        'https://rss.arxiv.org/rss/cs.LG+cs.AI+cs.CL+cs.CV');
    final r = await http
        .get(uri, headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return [];
    final f = RssFeed.parse(utf8.decode(r.bodyBytes, allowMalformed: true));
    return f.items.take(15).map((e) {
      return TrendEntry(
        title: cleanText(e.title),
        subtitle: cleanText(e.description),
        url: (e.link ?? '').trim(),
        metric: _shortDate(parseDate(e.pubDate?.toString())),
        source: 'arXiv',
      );
    }).where((e) => e.url.isNotEmpty).toList();
  } catch (_) {
    return [];
  }
}

/// Grab a page's <title> — used when a link is shared into the app.
Future<String?> fetchPageTitle(String url) async {
  try {
    final r = await http
        .get(Uri.parse(url), headers: {'User-Agent': kUserAgent})
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final m = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
        .firstMatch(body);
    if (m == null) return null;
    final t = cleanText(m.group(1));
    return t.isEmpty ? null : t;
  } catch (_) {
    return null;
  }
}

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String _shortDate(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inHours < 24) return 'today';
  return '${diff.inDays}d ago';
}
