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

/// The active sources behind the daily brief. Chosen to be clear, useful and
/// easy to read: plain-language titles, real knowledge — no jargon you'd need
/// a PhD to enjoy. Built for a working AI / ML / software engineer who also
/// likes sport and anime.
const kSources = <Source>[
  // ---------------------------------------------------------------- AI / ML
  // Easy-to-read AI news first, then practical learning material.
  Source('The Decoder', 'https://the-decoder.com/feed/', 'AI',
      cap: 2, ageH: 96, weight: 2, about: 'Clear, no-hype AI news.'),
  Source('The Verge AI',
      'https://www.theverge.com/rss/ai-artificial-intelligence/index.xml', 'AI',
      cap: 2, ageH: 72, weight: 2, about: 'AI news explained for normal people.'),
  Source('TechCrunch AI',
      'https://techcrunch.com/category/artificial-intelligence/feed/', 'AI',
      cap: 2, ageH: 72, about: 'New AI products, startups and funding.'),
  Source('TLDR AI', 'https://tldr.tech/api/rss/ai', 'AI',
      cap: 2, ageH: 72, about: 'The day in AI, in short summaries.'),
  Source('Ars Technica AI', 'https://arstechnica.com/ai/feed/', 'AI',
      cap: 1, ageH: 96, about: 'Practical AI news with real depth.'),
  Source('MIT Tech Review AI',
      'https://www.technologyreview.com/topic/artificial-intelligence/feed',
      'AI', cap: 1, ageH: 168, about: 'Trusted, well-explained AI stories.'),
  Source('AI News (Google)',
      'https://news.google.com/rss/search?q=artificial+intelligence+when:2d&hl=en-US&gl=US&ceid=US:en',
      'AI', cap: 2, ageH: 48, about: 'What the world is saying about AI today.'),
  Source('OpenAI', 'https://openai.com/news/rss.xml', 'AI',
      cap: 1, ageH: 240, weight: 2, about: 'Official OpenAI announcements.'),
  Source('Google DeepMind', 'https://deepmind.google/blog/rss.xml', 'AI',
      cap: 1, ageH: 240, weight: 2, about: 'Official DeepMind announcements.'),
  Source('Google AI', 'https://blog.google/technology/ai/rss/', 'AI',
      cap: 1, ageH: 168, about: 'New AI features from Google.'),
  Source('NVIDIA', 'https://blogs.nvidia.com/feed/', 'AI',
      cap: 1, ageH: 168, about: 'AI, GPUs and robotics from NVIDIA.'),
  Source('Hugging Face', 'https://huggingface.co/blog/feed.xml', 'AI',
      cap: 1, ageH: 168, about: 'New open models and tools, explained.'),
  Source('Machine Learning Mastery', 'https://machinelearningmastery.com/feed/',
      'AI', cap: 1, ageH: 240, about: 'Step-by-step ML tutorials.'),
  Source('KDnuggets', 'https://www.kdnuggets.com/feed', 'AI',
      cap: 1, ageH: 120, about: 'Data science tutorials and career tips.'),
  Source('Analytics Vidhya', 'https://www.analyticsvidhya.com/feed/', 'AI',
      cap: 1, ageH: 168, about: 'Beginner-friendly data science guides.'),
  Source('Towards Data Science', 'https://towardsdatascience.com/feed', 'AI',
      cap: 1, ageH: 96, about: 'Data science articles from practitioners.'),
  Source('MarkTechPost', 'https://www.marktechpost.com/feed/', 'AI',
      cap: 1, ageH: 96, about: 'AI research made readable.'),
  Source('r/LocalLLaMA', 'https://www.reddit.com/r/LocalLLaMA/top/.rss?t=day',
      'AI', cap: 1, ageH: 48, about: 'Run AI models on your own PC.'),
  Source('r/artificial', 'https://www.reddit.com/r/artificial/top/.rss?t=day',
      'AI', cap: 1, ageH: 48, about: 'Popular AI discussions.'),
  Source('r/datascience',
      'https://www.reddit.com/r/datascience/top/.rss?t=week', 'AI',
      cap: 1, ageH: 168, about: 'Data science jobs, tips and real talk.'),
  Source('r/learnmachinelearning',
      'https://www.reddit.com/r/learnmachinelearning/top/.rss?t=week', 'AI',
      cap: 1, ageH: 168, about: 'Beginners sharing ML resources.'),

  // ------------------------------------------------------- Dev / engineering
  // Practical, learn-something-today material.
  Source('Hacker News', 'https://hnrss.org/frontpage?points=150', 'Dev',
      cap: 3, ageH: 48, about: 'What tech people are reading right now.'),
  Source('Hacker News (best)', 'https://hnrss.org/best', 'Dev',
      cap: 1, ageH: 72, about: 'The best tech links of the moment.'),
  Source('GitHub Trending',
      'https://mshibanami.github.io/GitHubTrendingRSS/daily/all.xml', 'Dev',
      cap: 2, ageH: 48, about: 'Cool projects gaining stars today.'),
  Source('freeCodeCamp', 'https://www.freecodecamp.org/news/rss/', 'Dev',
      cap: 2, ageH: 120, weight: 2, about: 'Free, clear coding tutorials.'),
  Source('Real Python', 'https://realpython.com/atom.xml', 'Dev',
      cap: 1, ageH: 168, about: 'Python tutorials that are easy to follow.'),
  Source('DEV Community', 'https://dev.to/feed', 'Dev',
      cap: 2, ageH: 72, about: 'Developers sharing what they learned.'),
  Source('ByteByteGo', 'https://blog.bytebytego.com/feed', 'Dev',
      cap: 1, ageH: 240, about: 'How big systems work, with simple diagrams.'),
  Source('Simon Willison', 'https://simonwillison.net/atom/everything/', 'Dev',
      cap: 1, ageH: 120, about: 'Practical tips on using AI and Python.'),
  Source('GitHub Blog', 'https://github.blog/feed/', 'Dev',
      cap: 1, ageH: 168, about: 'New GitHub features and dev advice.'),
  Source('Google Developers', 'https://developers.googleblog.com/feed/', 'Dev',
      cap: 1, ageH: 168, about: 'New tools and APIs from Google.'),
  Source('r/learnprogramming',
      'https://www.reddit.com/r/learnprogramming/top/.rss?t=week', 'Dev',
      cap: 1, ageH: 168, about: 'Advice for people learning to code.'),
  Source('r/cscareerquestions',
      'https://www.reddit.com/r/cscareerquestions/top/.rss?t=week', 'Dev',
      cap: 1, ageH: 168, about: 'Tech jobs and internship advice.'),

  // ----------------------------------------- Science, ideas & useful knowledge
  // (category stays "Research" so it appears in your existing tab)
  Source('Our World in Data', 'https://ourworldindata.org/atom.xml', 'Research',
      cap: 1, ageH: 336, weight: 2,
      about: 'The world in clear charts and facts.'),
  Source('ScienceAlert', 'https://www.sciencealert.com/feed', 'Research',
      cap: 2, ageH: 72, about: 'Science discoveries in plain language.'),
  Source('Live Science', 'https://www.livescience.com/feeds/all', 'Research',
      cap: 2, ageH: 72, about: 'Amazing science, explained simply.'),
  Source('Science News', 'https://www.sciencenews.org/feed', 'Research',
      cap: 1, ageH: 72, about: 'Trusted science reporting, plainly told.'),
  Source('ScienceDaily', 'https://www.sciencedaily.com/rss/all.xml', 'Research',
      cap: 1, ageH: 72, about: 'New research summarised for everyone.'),
  Source('Futurism', 'https://futurism.com/feed', 'Research',
      cap: 1, ageH: 72, about: 'Future tech, space and AI curiosities.'),
  Source('Smithsonian Magazine',
      'https://www.smithsonianmag.com/rss/latest_articles/', 'Research',
      cap: 1, ageH: 120, about: 'History, science and culture stories.'),
  Source('Big Think', 'https://bigthink.com/feed/', 'Research',
      cap: 1, ageH: 120, about: 'Big ideas explained by experts.'),
  Source('Space.com', 'https://www.space.com/feeds/all', 'Research',
      cap: 1, ageH: 72, about: 'Space news and sky events.'),
  Source('NASA', 'https://www.nasa.gov/feed/', 'Research',
      cap: 1, ageH: 168, about: 'Official NASA news.'),
  Source('The Marginalian', 'https://www.themarginalian.org/feed/', 'Research',
      cap: 1, ageH: 336, about: 'Essays on living and thinking well.'),
  Source('James Clear', 'https://jamesclear.com/feed', 'Research',
      cap: 1, ageH: 336, about: 'Build better habits.'),
  Source('Paul Graham', 'http://www.aaronsw.com/2002/feeds/pgessays.rss',
      'Research', cap: 1, ageH: 2000,
      about: 'Timeless essays on work and startups.'),
  Source('Lifehacker', 'https://lifehacker.com/feed/rss', 'Research',
      cap: 1, ageH: 96, about: 'Practical tips for everyday life.'),
  Source('Quanta', 'https://api.quantamagazine.org/feed/', 'Research',
      cap: 1, ageH: 336, about: 'Beautiful math and science stories.'),
  Source('r/todayilearned',
      'https://www.reddit.com/r/todayilearned/top/.rss?t=day', 'Research',
      cap: 2, ageH: 48, weight: 2, about: 'Surprising facts people just learned.'),
  Source('r/explainlikeimfive',
      'https://www.reddit.com/r/explainlikeimfive/top/.rss?t=day', 'Research',
      cap: 1, ageH: 48, about: 'Complicated things explained simply.'),
  Source('r/science', 'https://www.reddit.com/r/science/top/.rss?t=day',
      'Research', cap: 1, ageH: 48, about: 'New studies in plain words.'),
  Source('r/Futurology', 'https://www.reddit.com/r/Futurology/top/.rss?t=day',
      'Research', cap: 1, ageH: 48, about: 'Where technology is heading.'),
  Source('r/LifeProTips',
      'https://www.reddit.com/r/LifeProTips/top/.rss?t=week', 'Research',
      cap: 1, ageH: 168, about: 'Small tricks that make life easier.'),
  Source('r/Documentaries',
      'https://www.reddit.com/r/Documentaries/top/.rss?t=week', 'Research',
      cap: 1, ageH: 168, about: 'The best documentaries people share.'),

  // ------------------------------------------------------------------- News
  Source('BBC News', 'https://feeds.bbci.co.uk/news/rss.xml', 'News',
      cap: 2, ageH: 36, about: 'Top stories from the BBC.'),
  Source('BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml', 'News',
      cap: 1, ageH: 36),
  Source('Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml', 'News',
      cap: 2, ageH: 36),
  Source('The Guardian', 'https://www.theguardian.com/world/rss', 'News',
      cap: 2, ageH: 36),
  Source('Google News',
      'https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en', 'News',
      cap: 3, ageH: 24, about: 'Top stories, aggregated.'),
  Source('TechCrunch', 'https://techcrunch.com/feed/', 'News',
      cap: 2, ageH: 48, about: 'Startups and tech business.'),
  Source('The Verge', 'https://www.theverge.com/rss/index.xml', 'News',
      cap: 2, ageH: 48, about: 'Gadgets, apps and internet culture.'),
  Source('Wired', 'https://www.wired.com/feed/rss', 'News',
      cap: 1, ageH: 72, about: 'How technology changes life.'),
  Source('MIT Tech Review', 'https://www.technologyreview.com/feed/', 'News',
      cap: 1, ageH: 96),
  Source('CNBC', 'https://www.cnbc.com/id/100003114/device/rss/rss.html',
      'News', cap: 1, ageH: 48, about: 'Business and money news.'),

  // ------------------------------------------------------------------ Video
  // A big mix of the best channels: learn AI/coding, science, tech, ideas.
  // Each channel shows its newest video, so the feed is always fresh.

  // -- AI & data (learn it)
  Source('Andrej Karpathy',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCXUPKJO5MZQN11PqgIvyuvQ',
      'Video', cap: 1, ageH: 720, weight: 3),
  Source('3Blue1Brown',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCYO_jab_esuFRV4b17AJtAw',
      'Video', cap: 1, ageH: 720, weight: 2),
  Source('Two Minute Papers',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCbfYPyITQ-7l4upoX8nvctg',
      'Video', cap: 1, ageH: 480),
  Source('AI Explained',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCNJ1Ymd5yFuUPtn21xtRbbw',
      'Video', cap: 1, ageH: 480),
  Source('Matt Wolfe',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UChpleBmo18P08aKCIgti38g',
      'Video', cap: 1, ageH: 480),
  Source('Matthew Berman',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCawZsQWqfGSbCI5yjkdVkTA',
      'Video', cap: 1, ageH: 480),
  Source('Sam Witteveen',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC55ODQSvARtgSyc8ThfiepQ',
      'Video', cap: 1, ageH: 480),
  Source('StatQuest',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCtYLUTtgS3k1Fg4y5tAhLbw',
      'Video', cap: 1, ageH: 480),
  Source('Lex Fridman',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCSHZKyawb77ixDdsGog4iWA',
      'Video', cap: 1, ageH: 720),
  Source('DeepLearning.AI',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCcIXc5mJsHVYTZR1maL5l9w',
      'Video', cap: 1, ageH: 480),

  // -- Coding & dev (learn it)
  Source('Fireship',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCsBjURrPoezykLs9EqgamOA',
      'Video', cap: 1, ageH: 480, weight: 2, about: 'Tech in 100 seconds.'),
  Source('freeCodeCamp (video)',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC8butISFwT-Wl7EV0hUK0BQ',
      'Video', cap: 1, ageH: 480, about: 'Full free coding courses.'),
  Source('CS50',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCcabW7890RKJzL968QWEykA',
      'Video', cap: 1, ageH: 1440, about: "Harvard's famous intro to CS."),
  Source('Traversy Media',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC29ju8bIPH5as8OGnQzwJyA',
      'Video', cap: 1, ageH: 480),
  Source('Programming with Mosh',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCWv7vMbMWH4-V0ZXdmDpPBA',
      'Video', cap: 1, ageH: 720),
  Source('Corey Schafer',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCCezIgC97PvUuR4_gbFUs5g',
      'Video', cap: 1, ageH: 2000, about: 'The clearest Python tutorials.'),
  Source('Tech With Tim',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC4JX40jDee_tINbkjycV4Sg',
      'Video', cap: 1, ageH: 480),
  Source('NetworkChuck',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC9x0AN7BWHpCDHSm9NiJFJQ',
      'Video', cap: 1, ageH: 480, about: 'Networking, Linux and cyber, made fun.'),
  Source('Flutter',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCwXdFgeE9KYzlDdR7TG9cMw',
      'Video', cap: 1, ageH: 720),
  Source('TechWorld with Nana',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCdngmbVKX1Tgre699-XLlUA',
      'Video', cap: 1, ageH: 720, about: 'DevOps, Docker and cloud made easy.'),
  Source('NVIDIA Developer',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCBHcMCGaiJhv-ESTcWGJPcw',
      'Video', cap: 1, ageH: 720),
  Source('Computerphile',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC9-y-6csu5WGm29I7JiwpnA',
      'Video', cap: 1, ageH: 720),

  // -- Science & big ideas
  Source('Veritasium',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCHnyfMqiRRG1u-2MsSQLbXA',
      'Video', cap: 1, ageH: 720, weight: 2),
  Source('Kurzgesagt',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCsXVk37bltHxD1rDPwtNM8Q',
      'Video', cap: 1, ageH: 720, weight: 2),
  Source('Vsauce',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC6nSFpj9HTCZ5t-N3Rm3-HA',
      'Video', cap: 1, ageH: 1440),
  Source('Mark Rober',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCY1kMZp36IQSyNx_9h4mpCg',
      'Video', cap: 1, ageH: 1440),
  Source('Smarter Every Day',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC6107grRI4m0o2-emgoDnAA',
      'Video', cap: 1, ageH: 1440),
  Source('Numberphile',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCoxcjq-8xIDTYp3uz647V5A',
      'Video', cap: 1, ageH: 720),
  Source('minutephysics',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCUHW94eEFW7hkUMVaZz4eDg',
      'Video', cap: 1, ageH: 1440),
  Source('SciShow',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCZYTClx2T1of7BRZ86-8fow',
      'Video', cap: 1, ageH: 480),
  Source('PBS Space Time',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC7_gcs09iThXybpVgjHZ_7g',
      'Video', cap: 1, ageH: 720),
  Source('TED',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCAuUUnT6oDeKwE6v1NGQxug',
      'Video', cap: 1, ageH: 480, about: 'Inspiring talks from great speakers.'),
  Source('TED-Ed',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCsooa4yRKGN_zEE8iknghZA',
      'Video', cap: 1, ageH: 720),
  Source('Crash Course',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCX6b17PVsYBQ0ip5gyeme-Q',
      'Video', cap: 1, ageH: 720),
  Source('Tom Scott',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCBa659QWEk1AI4Tg--mrJ2A',
      'Video', cap: 1, ageH: 2000),

  // -- How the world works (engineering, economy, geopolitics)
  Source('Real Engineering',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCR1IuLEqb6UEA_zQ81kwXfg',
      'Video', cap: 1, ageH: 1000),
  Source('Practical Engineering',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCMOqf8ab-42UUQIdVoKwjlQ',
      'Video', cap: 1, ageH: 720),
  Source('Wendover Productions',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UC9RM-iSvTu1uPJb8X5yp3EQ',
      'Video', cap: 1, ageH: 720),
  Source('PolyMatter',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCgNg3vwj3xt7QOrcIDaHdFg',
      'Video', cap: 1, ageH: 720),

  // -- Tech reviews & gear
  Source('Marques Brownlee',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCBJycsmduvYEL83R_U4JriQ',
      'Video', cap: 1, ageH: 480, weight: 2),
  Source('Mrwhosetheboss',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCMiJRAwDNSNzuYeN2uWa0pA',
      'Video', cap: 1, ageH: 480),
  Source('Linus Tech Tips',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCXuqSBlHAE6Xw-yeJA0Tunw',
      'Video', cap: 1, ageH: 480),

  // ------------------------------------------------------------------ Sport
  Source('BBC Sport', 'https://feeds.bbci.co.uk/sport/rss.xml', 'Sport',
      cap: 2, ageH: 48),
  Source('BBC Football', 'https://feeds.bbci.co.uk/sport/football/rss.xml',
      'Sport', cap: 2, ageH: 48),
  Source('The Guardian Football', 'https://www.theguardian.com/football/rss',
      'Sport', cap: 1, ageH: 48),
  Source('Sky Sports', 'https://www.skysports.com/rss/12040', 'Sport',
      cap: 1, ageH: 48),
  Source('Marca (EN)', 'https://e00-marca.uecdn.es/rss/en/index.xml', 'Sport',
      cap: 1, ageH: 48, about: 'Spanish football, in English.'),
  Source('Motorsport', 'https://www.motorsport.com/rss/all/news/', 'Sport',
      cap: 1, ageH: 72),
  Source('Atlas Lions & Botola',
      'https://news.google.com/rss/search?q=Morocco+national+football+team+OR+Botola+Pro&hl=en-US&gl=US&ceid=US:en',
      'Sport', cap: 2, ageH: 96, weight: 2, about: 'Moroccan football news.'),
  Source('Football Maroc (FR)',
      'https://news.google.com/rss/search?q=Lions+de+l%27Atlas+OR+Botola+OR+Wydad+OR+Raja&hl=fr&gl=MA&ceid=MA:fr',
      'Sport', cap: 2, ageH: 96),
  Source('Formula 1',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCB_qr75-ydFVKSF9Dmo6izg',
      'Sport', cap: 1, ageH: 336),
  Source('ESPN',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCiWLfSweyRNmLpgEHekhoAg',
      'Sport', cap: 1, ageH: 336),
  Source('Premier League',
      'https://www.youtube.com/feeds/videos.xml?channel_id=UCG5qGWdu8nIRZqJ_GgDwQ-w',
      'Sport', cap: 1, ageH: 336, about: 'Goals and highlights.'),
  Source('r/soccer', 'https://www.reddit.com/r/soccer/top/.rss?t=day', 'Sport',
      cap: 1, ageH: 48, about: 'Football news and big moments.'),

  // ------------------------------------------------------------------ Anime
  Source('Anime News Network', 'https://www.animenewsnetwork.com/all/rss.xml',
      'Anime', cap: 2, ageH: 96),
  Source('MyAnimeList News', 'https://myanimelist.net/rss/news.xml', 'Anime',
      cap: 2, ageH: 96),
  Source('Anime Corner', 'https://animecorner.me/feed/', 'Anime',
      cap: 2, ageH: 96, about: 'Rankings, new seasons and reviews.'),
  Source('Crunchyroll',
      'https://feeds.feedburner.com/crunchyroll/rss/anime', 'Anime',
      cap: 2, ageH: 96),
  Source('Otaku USA', 'https://otakuusamagazine.com/feed/', 'Anime',
      cap: 1, ageH: 168),
  Source('Anime Herald', 'https://www.animeherald.com/feed/', 'Anime',
      cap: 1, ageH: 168),
  Source('r/anime', 'https://www.reddit.com/r/anime/top/.rss?t=day', 'Anime',
      cap: 1, ageH: 48),

  // ---------------------------------------------------- PFE / internships
  // A daily sweep of final-year-project ("PFE") and internship openings:
  // Moroccan job boards, big-company careers and a few international boards.
  // All of it runs through Google News so we stay on plain RSS.
  Source('PFE Daba',
      'https://news.google.com/rss/search?q=site:pfedaba.ma&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 3, ageH: 336, weight: 3,
      about: 'Aggregated PFE listings across Morocco.'),
  Source('PFE IA Maroc',
      'https://news.google.com/rss/search?q=%22stage+PFE%22+IA+2027&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 3, ageH: 336, weight: 3,
      about: 'AI PFE and internship openings in Morocco.'),
  Source('PFE Data Science Maroc',
      'https://news.google.com/rss/search?q=%22stage+PFE%22+data+science&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, weight: 2,
      about: 'Data-science PFE placements.'),
  Source('PFE Machine Learning',
      'https://news.google.com/rss/search?q=%22stage+PFE%22+machine+learning&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336,
      about: 'Machine-learning PFE placements.'),
  Source('PFE Cloud & DevOps',
      'https://news.google.com/rss/search?q=%22stage+PFE%22+cloud+devops&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336,
      about: 'Cloud and DevOps PFE placements.'),
  Source('Stage pré-embauche IA',
      'https://news.google.com/rss/search?q=stage+pr%C3%A9-embauche+IA+Maroc&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, weight: 2,
      about: 'Internships that can turn into a first job.'),
  Source('Stage PFE 2027 Maroc',
      'https://news.google.com/rss/search?q=stage+PFE+2027+Maroc&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336,
      about: '2027 PFE placements as they open.'),
  Source('Rekrute',
      'https://news.google.com/rss/search?q=site:rekrute.com+PFE&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, about: 'Rekrute PFE and IT postings.'),
  Source('Emploi.ma',
      'https://news.google.com/rss/search?q=site:emploi.ma+PFE&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, about: 'Emploi.ma engineering and IT roles.'),
  Source('Maroc Emploi',
      'https://news.google.com/rss/search?q=site:marocemploi.net+stage&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, about: 'Moroccan internship announcements.'),
  Source('Dreamjob',
      'https://news.google.com/rss/search?q=site:dreamjob.ma+stage&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, about: 'Internships and graduate roles.'),
  Source('Indeed Maroc',
      'https://news.google.com/rss/search?q=site:ma.indeed.com+stage+PFE&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336, about: 'Indeed Morocco PFE listings.'),
  Source('LinkedIn PFE Maroc',
      'https://news.google.com/rss/search?q=site:linkedin.com+stage+PFE+Maroc&hl=fr&gl=MA&ceid=MA:fr',
      'PFE', cap: 2, ageH: 336,
      about: 'Recruiter posts and PFE roles on LinkedIn.'),
  Source('Internships abroad',
      'https://news.google.com/rss/search?q=software+engineering+intern+2027&hl=en-US&gl=US&ceid=US:en',
      'PFE', cap: 2, ageH: 336,
      about: 'Software internships outside Morocco.'),
  Source('ML internships abroad',
      'https://news.google.com/rss/search?q=machine+learning+internship+2027+Europe&hl=en-US&gl=US&ceid=US:en',
      'PFE', cap: 2, ageH: 336,
      about: 'Machine-learning internships in Europe.'),
  Source('Data internships abroad',
      'https://news.google.com/rss/search?q=data+engineering+internship+2027&hl=en-US&gl=US&ceid=US:en',
      'PFE', cap: 2, ageH: 336,
      about: 'Data-engineering internships abroad.'),
  Source('Stage IA France',
      'https://news.google.com/rss/search?q=%22stage+fin+d%27%C3%A9tudes%22+IA+France&hl=fr&gl=FR&ceid=FR:fr',
      'PFE', cap: 2, ageH: 336,
      about: 'French end-of-studies AI internships.'),
  Source('r/Morocco',
      'https://www.reddit.com/r/Morocco/top/.rss?t=week',
      'PFE', cap: 1, ageH: 168,
      about: 'Moroccan community: jobs, PFE and advice.'),
  Source('r/cscareerquestionsEU',
      'https://www.reddit.com/r/cscareerquestionsEU/top/.rss?t=week',
      'PFE', cap: 1, ageH: 168,
      about: 'Tech internships and careers in Europe.'),
];

/// Fetch every source, gently by host group.
///
/// Ordinary feeds run in a few parallel lanes. YouTube gets its own wider lane:
/// its RSS answers are small but it 404s under load, so we keep the gap short
/// and retry just the misses once. Reddit rate-limits hard, so it stays strictly
/// one-at-a-time. Crucially the three groups run *concurrently* — the video
/// lane no longer waits for every other feed to finish (and vice versa), so a
/// refresh takes as long as the slowest group instead of their sum.
Future<List<List<Item>>> fetchAllSources(List<Source> sources) async {
  final results = List<List<Item>>.generate(sources.length, (_) => const []);

  final reddit = <int>[];
  final video = <int>[];
  final fast = <int>[];
  for (var i = 0; i < sources.length; i++) {
    final host = Uri.tryParse(sources[i].url)?.host ?? '';
    if (host.contains('reddit.com')) {
      reddit.add(i);
    } else if (host.contains('youtube.com')) {
      video.add(i);
    } else {
      fast.add(i);
    }
  }

  // Everything except the rate-limited hosts: a handful of parallel lanes.
  Future<void> runFast() async {
    var cursor = 0;
    Future<void> lane() async {
      while (cursor < fast.length) {
        final index = fast[cursor++];
        results[index] = await fetchSource(sources[index]);
      }
    }

    await Future.wait(List.generate(8, (_) => lane()));
  }

  // YouTube: a wider lane so ~40 channels clear quickly, then one quiet retry
  // for whatever came back empty. Bounded so a hung host cannot hold up the
  // whole brief.
  Future<void> runVideo() async {
    await _fetchGentle(video, 6, sources, results,
        gap: const Duration(milliseconds: 60));
    final missed = video.where((i) => results[i].isEmpty).toList();
    if (missed.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 400));
      await _fetchGentle(missed, 3, sources, results,
          gap: const Duration(milliseconds: 250));
    }
  }

  // Reddit rate-limits hard: one at a time, with a gap.
  Future<void> runReddit() async {
    for (final index in reddit) {
      results[index] = await fetchSource(sources[index]);
      await Future.delayed(const Duration(milliseconds: 1800));
    }
  }

  await Future.wait([
    runFast(),
    runReddit(),
    runVideo().timeout(const Duration(seconds: 30), onTimeout: () {}),
  ]);

  return results;
}

/// Fetch [indices] with at most [width] requests in flight, pausing [gap]
/// between calls so flaky hosts stay happy.
Future<void> _fetchGentle(List<int> indices, int width, List<Source> sources,
    List<List<Item>> results,
    {Duration gap = const Duration(milliseconds: 200)}) async {
  var cursor = 0;
  Future<void> worker() async {
    while (cursor < indices.length) {
      final index = indices[cursor++];
      results[index] = await fetchSource(sources[index]);
      await Future.delayed(gap);
    }
  }

  await Future.wait(List.generate(width, (_) => worker()));
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
        // YouTube's RSS answers fast and 404s fast, so it does not need the
        // longer budget that slower feeds get.
        .timeout(Duration(seconds: s.cat == 'Video' ? 12 : 20));
    if (r.statusCode != 200) return [];
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    final out = <Item>[];

    // YouTube puts the real blurb in <media:description>, not <description>.
    final videoDescs = RegExp(
            r'<media:description>([\s\S]*?)</media:description>')
        .allMatches(body)
        .map((m) => cleanText(m.group(1)))
        .toList();
    // ...and the view count in <media:statistics views="…"/>, in entry order.
    final videoViews = RegExp(r'<media:statistics[^>]*views="(\d+)"')
        .allMatches(body)
        .map((m) => int.tryParse(m.group(1)!) ?? 0)
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
          views: i < videoViews.length ? videoViews[i] : 0,
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
          RegExp(r'The post .*? appeared first on .*?\.', caseSensitive: false),
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
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
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
      final tag = (e['pipeline_tag'] ?? '').toString();
      final lib = (e['library_name'] ?? '').toString();
      final tags = (e['tags'] as List? ?? const [])
          .map((t) => t.toString())
          .where((t) => t.isNotEmpty && t != tag)
          .take(4)
          .join(', ');
      return TrendEntry(
        title: (e['modelId'] ?? e['id'] ?? '').toString(),
        subtitle: tag.isNotEmpty ? tag : (lib.isNotEmpty ? lib : tags),
        url: 'https://huggingface.co/${e['modelId'] ?? e['id']}',
        metric: '${_compact(downloads)} dl',
        source: 'Hugging Face',
        tag: tag,
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
