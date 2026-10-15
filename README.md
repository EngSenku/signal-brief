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

**Brief** — ~32 ranked items drawn from **132 sources** across nine categories:
AI, Dev, Research, News, Video, Sport, Anime and Morocco (plus All). Category
chips make it easy to jump straight to your field. Tap any item to see a real
"What it's about" preview (the article's opening paragraphs, or the video's
description with a thumbnail) before you decide to open it. Ends with a
"You're caught up" card — no infinite scroll.

**Trends** — rising repositories (GitHub), trending models (Hugging Face) and
new papers (arXiv) for the week. Save any of them to your reading list.

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
list.

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
  screens/                  brief, trends, study, saved, settings, report, item
  services/
    notifications.dart      one daily reminder
    sharing.dart            receive links shared from other apps
```

Share-to-app on Android is implemented in-house: the `SEND` intent filter is in
`AndroidManifest.xml` and `MainActivity.kt` forwards the text to Dart over the
`signal/share` method channel (no third-party plugin to keep version-aligned).

## Tests

```bash
flutter test
```

Covers the SM-2 scheduler, model serialisation, feed parsing/cleaning, the
readable-text extractor, and widget smoke tests for every tab.

## Notes / limitations

- **iOS share-to-app** needs a Share Extension target added in Xcode. The
  Android path works out of the box via `MainActivity.kt`; iOS is not wired up.
- **Feed URLs** are best-effort. Reddit rate-limits aggressively, so those
  sources are fetched one at a time with a browser-like user agent; YouTube's
  RSS returns 404 when hit too fast, so it runs in its own small lane and any
  empty result is retried once. Any source that still fails is simply skipped on
  that refresh.
- The AI features need a valid NVIDIA key with available credit. Provide one via
  `.env` (or `--dart-define`), or paste it in Settings on first run.

## License

MIT — see [LICENSE](LICENSE).
