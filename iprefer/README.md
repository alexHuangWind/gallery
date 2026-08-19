# I prefer

Photograph one small thing you like, caption it `I prefer ...`, and keep a quiet
record of your taste — anchored to *when* and *where* you liked it.

Flutter, iOS and Android. Local-only: no backend, no accounts, no network except
map tiles.

---

## Status

**This code has never been compiled.** It was written in an environment with no
Flutter SDK. Three adversarial review passes have gone over it — data/logic,
runtime, and compile correctness (the last checking every third-party call
against the actual package sources for the declared versions) — and the defects
they found are fixed. That is thorough static analysis, and it is *not* a build.

Nothing here is validated automatically: this fork has no CI. Run it yourself
before trusting it.

```bash
cd iprefer
flutter pub get
flutter analyze
flutter test
flutter run
```

---

## What it's for

The product bets, in the order they matter — these are load-bearing, and the
code is shaped around them:

- **The MVP (free) bets on the recording habit.** People will keep noting things
  they like. That's retention, and it's the only thing this build chases.
- **v2 (subscription) bets on AI enhancement** — turning a casual snapshot into
  something postable. Not built here.
- **Already concluded false:** that plain-photo cards drive sharing. So the MVP
  does **not** chase sharing. The share button exists and is deliberately
  secondary.

Place and time serve the first bet, not the third. A place is a memory hook: it
gives the app a reason to be reopened that doesn't depend on an audience.

Copy throughout is lowercase, observational, specific — "ferns that uncurl like
a slow question", not "Capture your moment!". Empty states invite action, errors
explain plainly.

---

## Running it

### iOS (needs a Mac with Xcode)

`ios/` is generated rather than checked in. `Runner.xcodeproj/project.pbxproj`
is a machine-built file full of UUIDs; a hand-written one that couldn't be
verified here would be a liability. Bootstrap once:

```bash
cd iprefer
./tool/setup_ios.sh
flutter run
```

The script generates the Xcode project, adds the permission usage strings iOS
requires, pins the deployment target to 12.0 for `geolocator`, and runs
`pod install`. It is idempotent — safe to re-run.

**The permission strings matter.** On iOS a missing usage string is a **hard
crash**, not a denial. `flutter create` does not generate them, which is why the
script exists. If you ever regenerate the iOS project by hand, put these back:

| Key | Why |
|---|---|
| `NSLocationWhenInUseUsageDescription` | anchoring an entry to a place |
| `NSCameraUsageDescription` | taking the photo |
| `NSPhotoLibraryUsageDescription` | choosing an existing photo |
| `NSPhotoLibraryAddUsageDescription` | saving the finished card |

Only **when-in-use** location is ever requested. There is no background
tracking.

### Android

```bash
cd iprefer
flutter pub get
flutter run
```

`flutter pub get` writes `android/local.properties` on first build. The manifest
declares `INTERNET` (map tiles need it in release, not just debug) plus coarse
and fine location, both optional at runtime.

If the Android platform files ever get out of sync, regenerate them without
touching `lib/` or `pubspec.yaml`:

```bash
flutter create --platforms=android --org com.iprefer .
```

---

## What's built

| | |
|---|---|
| **Stub login** | a "continue" screen minting a *local* user id. No auth. |
| **Compose** | pick or take a photo, write the `I prefer ...` line, add tags. |
| **The card** | the centerpiece — see below. |
| **Card screen** | primary **save**, secondary **share** (system share of the exported PNG). |
| **Timeline** | grid of entries, newest first. Long-press to remove. |
| **Map** | second tab: located entries as photo pins over OpenStreetMap. |
| **Place + time** | every entry records the moment and, when available, coordinates and a place name. |
| **Return-to-place recall** | standing somewhere you've recorded before resurfaces what you liked there. |
| **Tags** | label an entry on the way in; one filter drives both tabs. |
| **Sort** | newest-first, or nearest-first by distance from where you're standing. |

---

## The card

The real leverage, and the thing to get right. First principle: **don't fight
the photo.** The card is 90% the photo; the layout only avoids ruining it.

- Full-bleed photo, portrait 9:16 — Story-ready.
- Bottom scrim: a gradient from transparent to a **dark tone pulled from the
  photo itself**. The bottom region is sampled with `palette_generator` and the
  value dropped in HSV. Never pure black, never a loud colour.
- `I prefer` in serif italic at ~80% white — the signature lockup.
- The user's words larger, serif, white, with a soft shadow for legibility.
- Date (and place, when known) on one quiet sans line: `mar 3, 2026 · fitzroy`.
- A tiny low-opacity `iprefer` wordmark in the corner.
- **One serif and one sans. No stickers, frames, or outside colour.**

Rendered inside a `RepaintBoundary` and exported via `toImage()` → PNG.

The serif is **Playfair Display** (OFL, bundled in `assets/fonts/`) so the card
looks right regardless of device fonts. The licence ships alongside it.

---

## Structure

```
lib/
  main.dart                     # guarded startup, providers, login/timeline routing
  theme.dart                    # paper-and-ink palette; chrome stays out of the way

  models/entry.dart             # Entry, hand-written Hive adapter, and the pure
                                #   helpers both production and tests call:
                                #   normalizeTags, haversineMetres,
                                #   entriesWithAnyTag, sortedByDistanceFrom

  data/entry_store.dart         # Hive CRUD, tag + proximity queries, photo files
  data/location_service.dart    # permission posture, fixes, reverse geocoding
  data/archive_view.dart        # tag selection + sort, shared by timeline and map
  data/session.dart             # stubbed local "login"

  widgets/preference_card.dart  # the card + palette scrim + capturePng
  widgets/nearby_recall.dart    # "you've been here before"
  widgets/tag_input.dart        # compose-time tag editor
  widgets/tag_filter_bar.dart   # tag filter chips
  widgets/sort_bar.dart         # newest / nearest toggle

  screens/login_screen.dart
  screens/home_shell.dart       # two tabs: timeline + map
  screens/compose_screen.dart
  screens/card_screen.dart
  screens/archive_screen.dart   # the timeline
  screens/map_screen.dart
```

State is plain `provider` (`ChangeNotifier`). No heavy architecture — the app is
small and should stay legible.

---

## How location behaves

Location is an **enhancement, never a requirement**. `LocationService` returns a
value or `null` and never throws, so a declined prompt or a cold GPS cannot
block recording. Two deliberately different postures:

- **`current(prompt: true)`** — used where the user just asked for something:
  after choosing a photo in compose, and when switching the timeline to
  "nearest". A permission dialog there has a visible reason attached.
- **`passive()`** — used by surfaces that appear on their own (the map, the
  recall banner). Returns `null` unless permission *already* exists, so neither
  ever raises a dialog on launch. It reads the OS cache first and falls back to
  a live read, because `getLastKnownPosition` commonly returns null on iOS. A
  cached fix older than 10 minutes is discarded — otherwise yesterday's fix
  would announce "you've been here before" about a city you have since left.

Both the map and the recall banner refresh on app resume. `IndexedStack` keeps
both tabs alive for the whole session, so without that they would answer for
wherever the app was launched.

Recall radius is 200 m — tight enough to mean *this* place, loose enough to
survive consumer-GPS drift. Distance is haversine, clamped so near-antipodal
points can't produce NaN.

---

## How tags behave

- **Normalized by the `Entry` constructor**, not by convention: lowercased,
  whitespace collapsed, a leading `#` dropped, deduped, capped at 24
  *characters*. "Wine" and " wine " cannot split one shelf into two, and no
  caller can store a raw tag by forgetting.
- The cap counts characters, not UTF-16 code units — otherwise two different
  emoji tags truncate to the same prefix and silently merge.
- **Filtering is OR**: more tags show *more*. "wine" plus "grocery" returns
  everything under either shelf; "all" clears the selection.
- Suggestions come from tags you've already used, most-used first, so the
  vocabulary is yours. The three seed tags appear only until you have your own.
- **Tags are never drawn on the card.** They're an organizing tool, not part of
  the artifact. They render *under* the card, outside the `RepaintBoundary`, and
  stay out of the exported PNG.
- The selection is pruned when a tag stops existing — otherwise deleting your
  last "wine" entry and recording a new one months later would collapse the
  archive onto a filter you'd long since cleared.

---

## How sorting behaves

- **newest** (default) — plain recency, and the order the store already returns,
  so it costs nothing.
- **nearest** — great-circle distance from where you're standing. Entries with
  no fix sort last, held newest-first by an explicit tiebreak, because Dart's
  `List.sort` is not stable and they would otherwise reshuffle every rebuild.

If no fix can be had, "nearest" stays selected and says *"needs your location ·
try again"* rather than snapping back — a control that silently reverts reads as
broken. The list falls back to newest-first meanwhile: a missing fix degrades
the ordering, it never empties the archive.

---

## Storage

Hive, one box of `Entry`:

```dart
class Entry {
  String id;
  String localPath;    // photo file NAME, resolved by EntryStore.fileFor
  String text;         // the "I prefer ..." line, without the prefix
  DateTime createdAt;
  double? latitude;    // null is normal
  double? longitude;
  String? placeLabel;  // reverse-geocoded, best effort
  List<String> tags;
}
```

Things worth knowing before you change this:

- **The adapter is hand-written** (`EntryAdapter`, `typeId: 1`) so there's no
  `build_runner` step. If you add a field, bump the field count *and* give it a
  new id — reads are keyed by id, which is what makes old records still load.
- **Reads are deliberately defensive.** `openBox` is non-lazy: it deserializes
  the whole archive at startup, so one torn record with a hard cast would throw
  before `runApp` and leave a permanently black screen. Startup is guarded too.
- **Photos are stored by file name, not absolute path.** iOS regenerates the app
  container UUID on reinstall and some OS updates, which would dangle every path
  at once. `EntryStore.fileFor` resolves names and keeps an absolute branch so
  records written earlier still load.
- **Delete removes the record first, the photo second.** An orphaned file is
  invisible and costs only disk; an orphaned record is a permanently broken tile
  the app offers no way to repair.

---

## Tests

```bash
flutter test
```

| file | covers |
|---|---|
| `entry_adapter_test.dart` | current-version Hive round-trips, located and unlocated |
| `legacy_adapter_test.dart` | hand-built 4-field and 7-field on-disk records still read |
| `proximity_test.dart` | haversine distances, the infinity sentinel, radius bounds |
| `tags_test.dart` | normalization, OR filtering, `hasTag` matching |
| `sort_test.dart` | distance ordering, the unlocated tiebreak, the NaN-antipode case |

Tests call the **production** functions (`normalizeTags`, `haversineMetres`,
`entriesWithAnyTag`, `sortedByDistanceFrom`). An earlier version re-implemented
that logic inside the tests and asserted against the copy — inverting OR to AND
in production left every test green. If you add logic, put it somewhere the
tests can reach rather than duplicating it.

`legacy_adapter_test.dart` reaches into Hive's internals to build old byte
layouts. It is isolated in its own file so a Hive upgrade that moves those paths
breaks only that file, not the whole suite.

---

## Before shipping

- **Map tiles** come from OpenStreetMap's public servers — fine for development
  and low volume, **not** a production tile source. Swap the `urlTemplate` in
  `screens/map_screen.dart` for your own provider (Mapbox, Stadia, Protomaps).
  Keep the `© OpenStreetMap` attribution if you stay on OSM; the licence
  requires it.
- **`Color.withOpacity`** is used in 17 places and was deprecated in Flutter
  3.27 for `withValues(alpha:)`. It is left alone deliberately: switching breaks
  SDKs older than 3.27, not switching breaks newer ones, and with no known SDK
  to compile against, guessing is worse than saying so. If your Flutter reports
  it as removed, the fix is mechanical — `x.withOpacity(0.8)` becomes
  `x.withValues(alpha: 0.8)`.
- **Login is a local stub.** `data/session.dart` and `screens/login_screen.dart`
  carry `TODO(firebase)` markers showing exactly where Google sign-in plugs in.
  The rest of the app reads `Session.signedIn` / `Session.userId` and won't
  change. Wiring it needs the owner's Firebase console.
- **Per-frame cost is unoptimized.** `tagCounts` / `tagsByUse` / `entries` each
  walk the whole box, and several widgets call them per build. Fine for a
  personal archive; memoize behind a dirty flag if it ever isn't.

---

## Not built, on purpose

AI enhancement (that's v2) · likes / public feed / follow · edit history ·
multi-language · multiple card templates · account management · cloud sync ·
any auth backend.

**v2, when it comes:** AI enhancement as the paid tier — free stays the
plain-photo card. Three candidate routes exist (full repaint /
enhance-not-replace / background-only) and *enhance-not-replace* is the one to
test first. Before any code: run a few real snapshots through an off-the-shelf
image AI by hand and see which output the owner would actually post. That answer
decides the approach.

See [`CLAUDE.md`](./CLAUDE.md) for the full product context and scope
boundaries.
