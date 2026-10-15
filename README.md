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

This is a personal project, not a product. Clone it and run it for yourself.

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
> be extracted. Rotate it if you share the build. The repo never contains it.

> Reasoning models (Nemotron and friends) think before they answer, which used to
> make summaries too long or cut off. Signal asks them to skip hidden reasoning
> (`enable_thinking: false`), retries only if needed, and never echoes
> chain-of-thought into the result.

## What's in it

**Brief.** Up to 20 items per category from 144 sources: AI, Dev, Research,
News, Video, Sport, Anime, PFE, plus an All view. Tap an item for a real
"What it's about" preview before you open it. The list ends with a "You're
caught up" card.

- **PFE & internships.** The last chip and the only uncapped one. Moroccan job
  boards (PFE Daba, Rekrute, Emploi.ma, Maroc Emploi, Dreamjob, Indeed, LinkedIn)
  plus international software, ML and data internships and Reddit threads, all
  through Google News.
- **Video.** The one category that ignores freshness: recent uploads ranked by
  view count, so an older popular video can beat a dull new one.

**Trends.** Weekly rising repos (GitHub), trending models (Hugging Face) and new
papers (arXiv). Tapping a card opens the same preview and AI summary as the
brief. Save any of them to your reading list.

**Media.** A personal offline library, not a feed, in two halves: **Music** and
**Video**. Share a YouTube link or paste it here and it saves to the device, then
plays offline. A saved clip opens full-screen with picture and sound. Delete an
item to reclaim the space.

Nothing is re-encoded: audio is YouTube's AAC track as `.m4a` (about 3 MB a
song), video is its ready-made 360p MP4 (about 12 MB). No transcoder in the APK.

**Study.**

- **Flashcards** from any item, generated with AI and reviewed with a simplified
  SM-2 schedule (Again / Hard / Good / Easy).
- **Paper of the week**, with a plain-language "In plain terms" explanation.
- **Learning goals** with progress tracking and a reading-day streak.

**Reading list.** Saved items with notes, tags and search. Articles are extracted
and cached for offline reading.

**Weekly report.** What you read, your top topics and sources, cards reviewed,
papers explained, a 7-day bar chart, and an optional AI summary.

**Share into Signal.** Share a link from any app and it lands in your reading
list. A YouTube link is offered to the Media library instead.

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

Share-to-app on Android is done in-house: a `SEND` intent filter in
`AndroidManifest.xml`, forwarded to Dart by `MainActivity.kt` over the
`signal/share` channel. No third-party plugin.

## Tests

```bash
flutter test
```

46 tests: the SM-2 scheduler, model serialisation, feed parsing, the
readable-text extractor, YouTube link parsing, and a widget test per tab.

## Notes and limitations

- **iOS share-to-app** needs a Share Extension target added in Xcode. Android
  works out of the box.
- **Feeds are best-effort.** Ordinary feeds, YouTube and Reddit are fetched
  concurrently, so a refresh takes as long as the slowest group. Reddit
  rate-limits hard, so it goes one source at a time; YouTube gets a wider lane. A
  source that fails is skipped for that refresh.
- **The AI features** need a valid NVIDIA key with credit, from `.env`,
  `--dart-define`, or Settings.
- **Media downloads** use `youtube_explode_dart`. Songs play through
  `just_audio`; a saved clip goes through `video_player` so the picture shows.
  Only one of the two ever plays. Media comes from the InnerTube player API, never
  the watch page, and metadata from oEmbed. Nothing is transcoded, and
  `video_player` adds only about 0.3 MB.
- **Why the VISIONOS client.** YouTube now wants a "PO token" from logged-out
  clients. Without one it still returns an audio URL, but that URL stops at 1 MB
  with a `403`, which looks like a download stuck at 0%. VISIONOS is not asked for
  a token, but needs the anonymous `visitorData` value that
  `youtube_explode_dart` only sends for `IOS`. Signal fetches that once per run
  and caches it. Video still needs an Android client, since only those offer
  YouTube's ready-made 360p MP4.
- **Download speed** depends on YouTube's throttling, which is why Signal keeps
  media small instead of transcoding or grabbing 4K. It uses the first working
  client, retries if the server goes quiet for 15s, and shows live speed and ETA.
- **For personal use, not for shipping.** Cloning this and running it yourself is
  fine, that is what it is for. Downloading from YouTube does break YouTube's
  Terms of Service, and the extractor depends on YouTube's internals, so please
  don't publish it to a store or run it as a service for others.

## License

MIT. See [LICENSE](LICENSE).
