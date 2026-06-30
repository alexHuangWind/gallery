# I prefer

Photograph one small thing you like, caption it `I prefer ...`, and keep a quiet,
shareable record of your taste. Flutter, Android-first.

This is the **local-only MVP** described in [`CLAUDE.md`](./CLAUDE.md): no backend,
no Firebase, login stubbed. It chases the *recording habit*, not sharing.

## Run it

You need the Flutter SDK (3.x) and an Android emulator or device.

```bash
cd iprefer
flutter pub get
flutter run
```

`flutter pub get` generates `android/local.properties` (pointing at your SDK) on
first build. If the Android platform files ever get out of sync, you can
regenerate them without touching `lib/` or `pubspec.yaml`:

```bash
flutter create --platforms=android --org com.iprefer .
```

## What's built

- **Stub login** — a "continue" screen that mints a *local* user id (no auth).
- **Compose** — pick/take a photo + write the `I prefer ...` line → "make card".
- **Preference card** — the centerpiece: full-bleed 9:16 photo, a bottom scrim
  whose color is pulled from the photo's own bottom region (sampled with
  `palette_generator`, value dropped in HSV — never pure black), serif-italic
  "I prefer" signature, the user's words in serif white with a soft shadow, and a
  tiny low-opacity `iprefer` wordmark. Rendered inside a `RepaintBoundary` and
  exportable to PNG.
- **Card screen** — primary **Save** (writes the entry) + secondary **Share**
  (system share of the exported PNG).
- **Timeline** — a grid of saved entries, newest first. Long-press to remove.
- **Local storage** — Hive (`Entry` box), photos copied into app documents.

The serif is **Playfair Display** (OFL), bundled in `assets/fonts/` so the card
looks right regardless of device fonts. The date uses the system sans.

## What's stubbed / out of scope (per spec)

- **Login is a local stub.** `lib/data/session.dart` and
  `lib/screens/login_screen.dart` carry `TODO(firebase)` markers showing exactly
  where Google sign-in plugs in for v2 — the rest of the app reads
  `Session.signedIn` / `Session.userId` and won't change.
- No AI enhancement (that's the v2 paid tier), no likes/feed/follow, no tags, no
  edit history, no cloud sync — all deliberately excluded from this pass.

## Structure

```
lib/
  main.dart                     # startup: open Hive + session, route login/timeline
  theme.dart
  models/entry.dart             # Entry + hand-written Hive adapter (no build_runner)
  data/entry_store.dart         # Hive CRUD + photo/PNG file helpers
  data/session.dart             # stubbed local "login"
  widgets/preference_card.dart  # the RepaintBoundary card + palette scrim + capturePng
  screens/login_screen.dart
  screens/compose_screen.dart
  screens/card_screen.dart
  screens/archive_screen.dart   # the timeline (home)
```

## Notes for development

- State is plain `provider` (`ChangeNotifier`) — no heavy architecture.
- The Hive adapter is hand-written (`EntryAdapter`, `typeId: 1`) so the project
  builds with no code-generation step. If you add fields, bump the field count
  and ids in `models/entry.dart` accordingly.
