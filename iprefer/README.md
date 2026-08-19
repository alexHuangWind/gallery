# I prefer

Photograph one small thing you like, caption it `I prefer ...`, and keep a quiet,
shareable record of your taste — anchored to *when* and *where* you liked it.
Flutter, iOS and Android.

This is the **local-only MVP** described in [`CLAUDE.md`](./CLAUDE.md): no backend,
no Firebase, login stubbed. It chases the *recording habit*, not sharing.

## Run it

You need the Flutter SDK (3.x).

### iOS (needs a Mac with Xcode)

The `ios/` folder is generated rather than checked in — `Runner.xcodeproj` is a
machine-built file full of UUIDs, and a hand-written one is a liability. Run the
bootstrap once:

```bash
cd iprefer
./tool/setup_ios.sh
flutter run
```

It generates the Xcode project, adds the permission usage strings iOS requires
(a missing one is a **crash**, not a denial), pins the deployment target to 12.0
for `geolocator`, and runs `pod install`.

### Android

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

### Required permission strings (iOS)

`tool/setup_ios.sh` adds these to `ios/Runner/Info.plist`. If you ever
regenerate the iOS project by hand, put them back or the app will crash the
moment it asks for location or the camera:

| Key | Why |
|---|---|
| `NSLocationWhenInUseUsageDescription` | anchoring an entry to a place |
| `NSCameraUsageDescription` | taking the photo |
| `NSPhotoLibraryUsageDescription` | choosing an existing photo |
| `NSPhotoLibraryAddUsageDescription` | saving the finished card |

We only ever request **when-in-use** location. There is no background tracking.

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
- **Tags** — label an entry while composing ("grocery", "wine", "dish").
  Suggestions come from tags you've already used, most-used first, so the
  vocabulary is yours; the three seed tags only appear until you have your own.
  One filter drives the timeline *and* the map, so "wine" + the map tab answers
  "where do I like wine?".
- **Sort** — the timeline reads newest-first by default, or **nearest-first**,
  which orders your entries by how far they are from where you're standing.
- **Place + time** — each entry records the moment and, when available, the
  coordinates and a reverse-geocoded place name. The place joins the date on the
  card's existing sans line (`mar 3, 2026 · fitzroy`) — no new type family.
- **Map** — second tab: every located entry as a photo pin on an OpenStreetMap
  view, tap to open its card. Shows where you liked what.
- **"You've been here before"** — returning to a place you've recorded surfaces
  what you liked there, at the top of the timeline. This is the retention
  mechanic: the app reintroduces you to your own taste.
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
  models/entry.dart             # Entry (+ location, tags) + hand-written Hive adapter
  data/entry_store.dart         # Hive CRUD, proximity + tag queries, file helpers
  data/location_service.dart    # permission, current/passive fix, reverse geocode
  data/archive_view.dart        # tag selection + sort, shared by timeline and map
  data/session.dart             # stubbed local "login"
  widgets/preference_card.dart  # the RepaintBoundary card + palette scrim + capturePng
  widgets/nearby_recall.dart    # "you've been here before" banner
  widgets/tag_input.dart        # compose-time tag editor
  widgets/tag_filter_bar.dart   # tag filter chips
  widgets/sort_bar.dart         # newest / nearest toggle
  screens/login_screen.dart
  screens/home_shell.dart       # two tabs: timeline + map
  screens/compose_screen.dart
  screens/card_screen.dart
  screens/archive_screen.dart   # the timeline
  screens/map_screen.dart       # the map
```

## How tags behave

- **Normalized on the way in** (`normalizeTags` in `models/entry.dart`):
  lowercased, whitespace collapsed, a leading `#` dropped, deduped, capped at 24
  characters. "Wine" and " wine " can never split one shelf into two.
- **Filtering is OR** — selecting more tags shows *more*, not less. Several
  chips can be lit at once; "wine" plus "grocery" returns everything under
  either shelf, and "all" clears the selection.
- Because the selection only ever holds tags that still exist, an OR filter can
  never come back empty while you have entries — so the timeline has no "your
  filter matched nothing" state to fall into.
- **Tags are not drawn on the card.** They're an organizing tool, not part of
  the artifact; the card spec allows one serif and one sans and no extra
  furniture, so tags appear *under* the card on its screen and never in the
  exported PNG.
- Filter and sort live together in a shared `ArchiveView`, and
  `ArchiveView.effective()` intersects the selection with the tags that still
  exist. Without that, deleting your last "wine" entry would leave the archive
  referring to a tag whose chip is no longer on screen to unset.

## How sorting behaves

- **newest** (default) — straight recency, and the order the store already
  returns, so it costs nothing.
- **nearest** — orders by great-circle distance from where you are standing.
  Entries with no location fix sort last, held in newest-first order by an
  explicit tiebreak (Dart's `List.sort` is not stable, so without it they would
  shuffle on every rebuild).
- Tapping "nearest" is the one place on the timeline that may raise a location
  prompt, and that is deliberate: the user just asked for a distance ordering,
  so the dialog has an obvious reason. If no fix can be had, the mode stays
  selected and says "needs your location · try again" rather than snapping back
  to newest, which would read as a broken control. The list falls back to
  newest-first meanwhile — a missing fix degrades the ordering, it never empties
  the archive.

## How location behaves

Location is an **enhancement, never a requirement** — `LocationService` returns
a value or `null` and never throws, so a declined prompt or a cold GPS can't
block recording. Two deliberately different postures:

- `LocationService.current(prompt: true)` — used in **compose**, right after the
  user picks a photo. They've just committed to recording something, so the
  system prompt has an obvious reason attached. They can also drop the place
  from a single entry with "leave it off".
- `LocationService.passive()` — used by the **map** and the **recall banner**.
  Returns `null` unless permission was *already* granted, so neither surface
  ever raises a permission dialog on launch. It tries the OS location cache
  first and falls back to a live read, because `getLastKnownPosition` commonly
  returns null on iOS.

The recall radius is 200 m (`NearbyRecall.radiusMetres`) — tight enough to mean
*this* place, loose enough to survive consumer-GPS drift. Distance is haversine
(`haversineMetres` in `models/entry.dart`).

## Notes for development

- State is plain `provider` (`ChangeNotifier`) — no heavy architecture.
- The Hive adapter is hand-written (`EntryAdapter`, `typeId: 1`) so the project
  builds with no code-generation step. If you add fields, bump the field count
  and ids in `models/entry.dart` accordingly. Reads are keyed by field id, so
  entries written before location existed still load — the missing ids come back
  `null`.
- **`Color.withOpacity` is used in ~14 places and was deprecated in Flutter
  3.27** in favour of `withValues(alpha:)`. It is left as-is deliberately:
  switching would break builds on SDKs older than 3.27, and this project has
  never been compiled against a known SDK, so guessing either way is worse than
  saying so. If your Flutter reports it as removed, the fix is mechanical —
  `x.withOpacity(0.8)` becomes `x.withValues(alpha: 0.8)`.
- **Map tiles** come from OpenStreetMap's public servers, which are fine for
  development and low volume but are *not* a production tile source. Before
  shipping at volume, swap the `urlTemplate` in `screens/map_screen.dart` for
  your own provider (Mapbox, Stadia, Protomaps). The `© OpenStreetMap`
  attribution on the map is required by the licence — keep it if you keep OSM.
