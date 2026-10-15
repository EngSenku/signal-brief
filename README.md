# Signal

<img src="assets/icon/icon_full.png" width="88" alt="Signal app icon">

A finite daily brief that replaces doomscrolling, plus study tools that turn what
you read into something you actually remember.

A Flutter app, Android-first. Everything is stored on the phone: your reading
list, your flashcards, the offline music and video library. The only network
calls are the feeds, the trends APIs, YouTube when you save media, and NVIDIA if
you switch AI on.

Every category ends. There is no infinite scroll and no algorithmic next-up, and
you can set a daily time limit that locks the app when it runs out.

## Run it

```bash
cp .env.example .env   # optional: paste your NVIDIA key to have AI ready out of the box
flutter pub get
flutter run            # pick your device
```

The key lives in `.env`, which is gitignored, so no secret is in source control.
It is read at startup; you can also pass it with `--dart-define=NVIDIA_API_KEY=…`.
Without a key everything works except the AI features.

Build installable APKs (one per ABI, arm64 covers almost every modern phone):

```bash
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   ~22 MB
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ~20 MB
# build/app/outputs/flutter-apk/app-x86_64-release.apk      ~23 MB
```

Built with Flutter 3.44 / Dart 3.12. Android is the supported target; the iOS
and desktop folders are there but untested.

## First run

1. Open **You → AI features**, paste an **NVIDIA API key** (`nvapi-…`) and tap
   **Test key**. A key you enter here wins over the bundled one and is kept in
   the OS keychain (`flutter_secure_storage`). Skip this step and the app just
   runs without AI.
2. Pick a model. The default is `nvidia/nemotron-3.5-lightning-30b-a3b`.
3. Optional: turn on the **daily reminder** and pick a time.
4. Optional: tune **boost topics**, **muted words** and **sources**.

> If you put a key in `.env` and ship the APK, that key is inside the APK and can
> be extracted. Treat it as public and rotate it if you share the build. The
> repository itself never contains it.

> Reasoning models such as Nemotron think before they answer, which used to make
> summaries come back too long or cut off. Signal asks the model to skip its
> hidden reasoning (`enable_thinking: false`), retries with a larger budget only
> if needed, and never echoes chain-of-thought into the result.

## What's in it

**Brief.** Up to 20 items per category from 144 sources, across AI, Dev,
Research, News, Video, Sport, Anime and PFE, plus an All view. Tapping an item
shows a real "What it's about" preview first: the article's opening paragraphs,
or a video's description and thumbnail. The list ends with a "You're caught up"
card.

- **PFE & internships** is the last chip and the only uncapped one. It sweeps
  Moroccan job boards (PFE Daba, Rekrute, Emploi.ma, Maroc Emploi, Dreamjob,
  Indeed, LinkedIn), plus international software, ML and data internships and
  relevant Reddit threads, all through Google News so it stays plain RSS.
- **Video** is the one category that ignores freshness. Each channel's recent
  uploads are ranked by view count, so a genuinely popular older video can beat a
  dull new one. View counts show on the card and in the sheet.

**Trends.** Rising repositories from GitHub, trending models from Hugging Face
and new papers from arXiv, for the week. Tapping a card opens the same
"What it's about" and AI-summary sheet as the brief, minus the flashcard action.
Save any of them to your reading list.

**Media.** A personal offline library, and deliberately not a feed. It has two
halves, **Music** and **Video**. Find a song or a video on YouTube (or YouTube
Music), tap **Share** and pick Signal, or paste the link on the Media tab. Signal
saves it on the device and plays it back in-app with a full player (seek,
next/previous, playlist), no connection needed afterwards. A saved clip is a real
video: tapping it opens a full-screen player with picture and sound, and it sits
in the Video half with a movie glyph so it never reads as a song. Delete an item
to reclaim the space.

Downloads are not re-encoded, so they run as fast as the network allows.
**Audio** saves YouTube's own AAC track as a `.m4a`, about 3 MB for a song.
**Video** saves YouTube's ready-made 360p MP4, with video and audio in one file,
about 12 MB. No transcode step, and no transcoder bundled into the APK.

**Study.**

- **Flashcards** from any item, generated with AI and reviewed with a simplified
  SM-2 schedule (Again / Hard / Good / Easy).
- **Paper of the week**, with a plain-language "In plain terms" explanation.
- **Learning goals** with progress tracking and a reading-day streak.

**Reading list.** Saved items with your own notes and tags, search, and offline
reading: the article body is extracted and cached on device.

**Weekly report.** What you read, your top topics and sources, cards reviewed,
papers explained, a 7-day bar chart, and an optional AI summary of your week.

**Share into Signal.** Share a link from any app and it lands in your reading
list. Share a YouTube link and Signal offers to keep it in the Media library as
audio or video instead.

**Time limit.** A daily budget with a lock screen and a "5 more minutes" button.

## Architecture

```
lib/
  main.dart                 app shell, nav, lifecycle, share + notification wiring
  models.dart               Item, Flashcard, Goal, TrendEntry, Trends, WeeklyStats
  store.dart                AppState, one ChangeNotifier holding all state
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
    music.dart              offline library: YouTube to local audio/video + playback
```

Share-to-app on Android is done in-house: the `SEND` intent filter lives in
`AndroidManifest.xml`, and `MainActivity.kt` forwards the text to Dart over the
`signal/share` method channel. No third-party plugin to keep version-aligned.

## Tests

```bash
flutter test
```

46 tests: the SM-2 scheduler, model serialisation, feed parsing and cleaning, the
readable-text extractor, YouTube link parsing, and widget tests for every tab
including the Media page.

## Notes and limitations

- **iOS share-to-app** needs a Share Extension target added in Xcode. The Android
  path works out of the box; iOS is not wired up.
- **Feeds are best-effort.** The three host groups (ordinary feeds, YouTube,
  Reddit) are fetched concurrently, so a refresh takes as long as the slowest
  group instead of their sum. Reddit rate-limits aggressively, so those sources
  are fetched one at a time with a browser-like user agent; YouTube gets a wider
  lane (short gap, a single retry for the misses, a 30s cap). Any source that
  still fails is skipped on that refresh.
- **The AI features** need a valid NVIDIA key with available credit, from `.env`,
  `--dart-define`, or the Settings screen.
- **Media downloads.** Items are downloaded from a link you choose, using
  `youtube_explode_dart`. Playback is split by what was saved: songs go through
  `just_audio`, a saved clip goes through `video_player` so its picture is
  actually shown. The two never play at once; whichever item is current owns
  playback, and the audio listeners stand down while a clip is loaded. Media is
  fetched from YouTube's InnerTube player API only, deliberately without touching
  the watch page, because YouTube sends watch-page requests to a rate-limit
  `/sorry/` page far more readily. Metadata comes from the oEmbed endpoint.
  Nothing is transcoded, so the app ships no media codecs and stays small:
  `video_player` adds only about 0.3 MB, because `just_audio` already bundles the
  same ExoPlayer/Media3 stack.
- **Why the VISIONOS client.** YouTube now asks most logged-out clients for a
  "PO token". A client without one still answers with an audio URL, but that URL
  only ever serves the **first megabyte** of the file and returns `403` past it,
  which is indistinguishable from a download stuck at 0%. The **VISIONOS** client
  is not asked for a PO token, but it needs the anonymous `visitorData` value
  that `youtube_explode_dart` only sends for its `IOS` client. Signal fetches that
  value once per run and caches it, which is what makes the audio URL complete.
  Video still comes from an Android client, the only kind that offers YouTube's
  ready-made muxed 360p file. If no client offers more than that 1 MB preview,
  Signal says so rather than pretending to download.
- **Download speed.** YouTube throttles these media URLs, so the wait scales with
  file size. That is why Signal keeps the media small (about 3 MB audio, 360p
  video) instead of transcoding or grabbing 4K. It stops at the first working
  InnerTube client instead of querying all of them, tears the request down and
  retries if the server goes quiet for 15s, and the progress line shows megabytes
  received with live speed and ETA so a slow link is visibly moving.
- Downloading from YouTube is against YouTube's Terms of Service, and the
  extractor depends on YouTube's internals. A busy IP can still get rate-limited.
  Use it for personal listening, and think twice before shipping it publicly.

## License

MIT. See [LICENSE](LICENSE).
