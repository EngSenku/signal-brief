# Signal

A finite, filtered, intentional daily brief that replaces doomscrolling — with
study tools that turn the news you read into things you remember.

Built with Flutter. Everything is stored locally on the phone; the only network
calls are to the RSS feeds, the trends APIs, and (optionally) NVIDIA for AI.

## Run it

```bash
cp .env.example .env   # optional: paste your NVIDIA key to enable AI out of the box
flutter pub get
flutter run            # pick your device
```

The key lives in `.env`, which is **gitignored** — nothing secret is in source
control. `.env` is read at startup; you can also pass it at build time with
`--dart-define=NVIDIA_API_KEY=…`. Without a key, everything except AI still
works and you can paste a key in Settings.

Build installable Android APKs:

```bash
flutter build apk --release --split-per-abi
# outputs (pick the one matching your phone — arm64 for almost all modern phones):
#   build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#   build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
#   build/app/outputs/flutter-apk/app-x86_64-release.apk
```

The `android/`, `ios/`, `web/` and `linux/` folders are all scaffolded. The
Android internet permission, notification permissions and the share-to-app
intent filter are already in `android/app/src/main/AndroidManifest.xml`.

## First-run setup

1. AI works out of the box **if** you built with a `.env` containing
   `NVIDIA_API_KEY` (or a `--dart-define`). Otherwise, open **You → AI
   features**, paste your **NVIDIA API key** (`nvapi-…`) and tap **Test key**.
   A key you enter here wins over the bundled one and is kept in the OS keychain
   (`flutter_secure_storage`).
2. Pick a model (default: `nvidia/nemotron-3.5-lightning-30b-a3b`).
3. Optional: turn on the **daily reminder** and pick a time.
4. Optional: tune **boost topics**, **muted words** and **sources**.

> **Heads-up on the key:** if you put a key in `.env` and ship the APK, that key
> is inside the APK and can be extracted — treat it as public and rotate it if
> you share the build. The repository itself never contains it.

> **Reasoning models** (Nemotron and friends) think before they answer, which
> used to make summaries come back too long or cut off. Signal now asks the
> model to skip its hidden reasoning (`enable_thinking: false`), retries with a
> larger budget only if needed, and never echoes chain-of-thought into the
> result. Switch models any time in Settings.

## What's in it

**Brief** — up to **20 items per category** drawn from **144 sources** across
AI, Dev, Research, News, Video, Sport, Anime and PFE, plus an All view. PFE is
uncapped: it pulls every listing it can find. Category chips make it easy to
jump straight to your field. Tap any item to see a real
"What it's about" preview (the article's opening paragraphs, or the video's
description with a thumbnail) before you decide to open it. Ends with a
"You're caught up" card — no infinite scroll.

- **PFE & internships** — the last chip in the bar, and the only uncapped one:
  it sweeps Moroccan job boards (PFE Daba, Rekrute, Emploi.ma, Maroc Emploi,
  Dreamjob, Indeed, LinkedIn) plus international software / ML / data
  internships and relevant Reddit threads, all through Google News so it stays
  plain RSS.
- **Video** — the one category that ignores freshness. Each channel's recent
  uploads are ranked by view count, so a genuinely popular older video can beat
  a dull new one. View counts are shown on the card and in the sheet.

**Trends** — rising repositories (GitHub), trending models (Hugging Face) and
new papers (arXiv) for the week. Every card shows what it is about, and tapping
one opens the same "What it's about" + AI-summary sheet as the brief (without
the flashcard action). Save any of them to your reading list.

**Music** — a personal, *offline* library, and deliberately **not** a feed.
Find a song or video on YouTube (or YouTube Music), tap **Share** and pick
Signal — or paste the link on the Music tab. Signal saves it on the device and
plays it back in-app with a full player (seek, next/previous, playlist), no
connection needed afterwards. A saved clip is a real video: tap it and it opens
full-screen with picture and sound, and its row is tagged **Video** with a movie
glyph so it never looks like a song. Delete an item to reclaim the space.

Nothing is re-encoded, so a download is as fast as the network allows:
**Audio** saves YouTube's own AAC track as a `.m4a` (about 3 MB for a song) and
**Video** saves YouTube's ready-made **360p** MP4 — video and audio in a single
file, about 12 MB. Both are exactly the media YouTube serves, with no transcode
step and no transcoder bundled into the apk (see the note on music below).

**Study**
- **Flashcards** generated from any item with AI, reviewed with a simplified
  SM-2 spaced-repetition schedule (Again / Hard / Good / Easy).
- **Paper of the week** with a plain-language "In plain terms" explanation.
- **Learning goals** with progress tracking and a reading-day streak.

**Reading list** — saved items with your own notes, tags, search, and offline
reading (the article body is extracted and cached on device).

**Weekly report** — what you read, your top topics and sources, cards reviewed,
papers explained, a 7-day bar chart and an optional AI summary of your week.

**Share into Signal** — share a link from any app and it lands in your reading
list. Share a YouTube link and Signal offers to download it into your offline
Music library as audio or video instead.

**Time limit** — a daily budget with a lock screen and a "5 more minutes"
button.

## Architecture

```
lib/
  main.dart                 app shell, nav, lifecycle, share + notification wiring
  models.dart               Item, Flashcard, Goal, TrendEntry, Trends, WeeklyStats
  store.dart                AppState — one ChangeNotifier holding all state
  ai.dart                   NVIDIA NIM client, error mapping, JSON extraction
  feeds.dart                sources, RSS/Atom parsing, trends fetchers
  study.dart                pure SM-2 scheduling logic
  article.dart              readable-text extraction + offline cache
  theme.dart                palette, theme, shared card/button widgets
  widgets.dart              stat boxes, chip row, progress bars, tags
  screens/                  brief, trends, study, saved, music, settings, report, item
  services/
    notifications.dart      one daily reminder
    sharing.dart            receive links shared from other apps
    music.dart              offline library: YouTube → local audio/video + playback
```

Share-to-app on Android is implemented in-house: the `SEND` intent filter is in
`AndroidManifest.xml` and `MainActivity.kt` forwards the text to Dart over the
`signal/share` method channel (no third-party plugin to keep version-aligned).

## Tests

```bash
flutter test
```

Covers the SM-2 scheduler, model serialisation, feed parsing/cleaning, the
readable-text extractor, YouTube link parsing for the music library, and widget
smoke tests for every tab.

## Notes / limitations

- **iOS share-to-app** needs a Share Extension target added in Xcode. The
  Android path works out of the box via `MainActivity.kt`; iOS is not wired up.
- **Feed URLs** are best-effort. The three host groups (ordinary feeds, YouTube,
  Reddit) are fetched **concurrently**, so a refresh takes as long as the slowest
  group instead of their sum — YouTube no longer waits behind everything else.
  Reddit rate-limits aggressively, so those sources are fetched one at a time
  with a browser-like user agent; YouTube gets a wider lane (short gap, a single
  retry for the misses, and a 30s cap). Any source that still fails is skipped on
  that refresh.
- The AI features need a valid NVIDIA key with available credit. Provide one via
  `.env` (or `--dart-define`), or paste it in Settings on first run.
- **Music downloads.** Items are downloaded from a link you choose, using
  `youtube_explode_dart`. Playback is split by what was saved: songs go through
  `just_audio`, while a saved clip goes through `video_player` so its picture is
  actually shown (the two never play at once — whichever item is current owns
  playback, and the audio listeners stand down while a clip is loaded). Media is
  fetched from YouTube's InnerTube
  player API only and deliberately *without* touching the watch page — YouTube
  sends watch-page requests to a rate-limit `/sorry/` page far more readily.
  Metadata comes from the oEmbed endpoint. **Nothing is transcoded**: audio is
  YouTube's AAC stream saved as `.m4a` and video is its ready-made 360p MP4, so
  the app ships no media codecs and stays small (`video_player` adds only ~0.3 MB,
  because `just_audio` already bundles the same ExoPlayer/Media3 stack).
- **Why the VISIONOS client.** YouTube now asks most logged-out clients for a
  "PO token". A client without one still answers with an audio URL, but that URL
  only ever serves the **first megabyte** of the file and answers `403` past it —
  which looks exactly like a download that hangs at 0 %. The **VISIONOS** client
  is not asked for a PO token, but it needs the anonymous `visitorData` value
  that `youtube_explode_dart` only sends for its `IOS` client. Signal fetches
  that value once per run (and caches it), sends it with VISIONOS, and so gets a
  complete audio URL. Video still comes from an Android client, which is the only
  kind that offers YouTube's ready-made muxed 360p file. If no client offers more
  than the one-megabyte preview, Signal says so instead of pretending to
  download. Downloading from YouTube is against YouTube's Terms of Service, the
  extractor depends on YouTube's internals, and a busy IP can still be
  rate-limited; use it for personal listening and think twice before shipping it
  publicly.
- **Download speed.** YouTube throttles these media URLs, so the wait scales
  with file size — which is exactly why Signal keeps the media small (≈3 MB
  audio, 360p video) instead of transcoding or grabbing 4K. It stops at the first
  working InnerTube client instead of querying all of them, the request is torn
  down and retried if the server goes quiet for 15 s, and the progress line shows
  megabytes received plus live speed and ETA so a slow link is visibly moving.

## License

MIT — see [LICENSE](LICENSE).
