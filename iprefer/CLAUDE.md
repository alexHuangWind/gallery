# I Prefer — project context for Claude Code

A mobile app where someone photographs a thing they love and captions it
`I prefer ...`, producing a quiet, shareable card. Built in **Flutter**.

> Read this fully before writing code. The scope boundaries below are
> deliberate — do not expand them without being asked.

## What we're betting on (don't blur these layers)

- **MVP (free)** bets that people will **keep recording** things they like (retention).
- **v2 (subscription)** bets that people will pay for **AI enhancement** that turns a
  casual snapshot into something postable.
- **Already concluded false, not being bet on:** that plain-photo cards drive sharing.
  So the MVP does **not** chase sharing — it chases the recording habit.

## MVP scope (build ONLY this first — local-only, no backend yet)

1. Take / pick a photo + write one line `I prefer ...`
2. **Generate the card** (the centerpiece — see Card spec)
3. **Timeline** of past entries (a slow self-portrait of taste)
4. **Place + time** — record when and (when available) where each entry happened
5. **Map** of your entries — see where you liked what
6. **Return-to-place recall** — arriving somewhere you've recorded before
   resurfaces what you liked there
7. **Tags** — label an entry on the way in ("grocery", "wine", "dish"); one
   filter narrows both the timeline and the map. Tags never render on the card.
8. **Share button** — present but secondary (system share of the rendered image)
9. **Login is stubbed for now** — a placeholder "continue" that sets a local user id.
   Do NOT wire Firebase / Google sign-in yet; that needs the owner's console setup.

Local storage only (Hive). No cloud sync, no Firestore, no auth backend in this pass.

Items 4-7 were added after the first build. They serve the same bet as the rest of
the MVP — **retention, not sharing**. Place is a memory hook: it gives the app a
reason to be reopened that doesn't depend on an audience. Location is always
optional; a declined permission must never block recording.

## Explicitly NOT in this build

AI features (that's v2) · likes / public feed / follow · edit history ·
multi-language · multiple card templates · password/account management.

(Tags were originally excluded here and have since been added at the owner's
request — see scope item 9. They stay off the card itself.)

## Card spec (the real leverage — get this right)

First principle: **don't fight the photo.** The card is 90% the photo; layout just
avoids ruining it.

- Full-bleed photo, portrait 9:16 (Story-ready).
- Bottom scrim: linear gradient transparent → a **dark tone pulled from the photo**
  (sample the bottom region's dominant color, drop its value in HSV). Not pure black.
- `I prefer` in a **serif italic**, smaller, ~80% white — the signature lockup.
- The user's words larger, serif, white, with a soft text shadow for legibility.
- Tiny low-opacity `iprefer` wordmark, bottom corner.
- One type family (serif + a sans for the date). No stickers / frames / outside colors.
- Render via `RepaintBoundary` → `toImage()`; extract color with `palette_generator`.

A reference render already exists and the approach is validated; the weak point is
photo quality itself, which is what v2's AI solves — not the layout.

## Tech & conventions

- **Flutter / Dart**, null-safe. Target Android first (iOS is a free bonus later).
- State: keep it simple — Provider or Riverpod, your call; no heavy architecture.
- Storage: **Hive** (or sqflite) for local entries.
- Card export: `RepaintBoundary` + `ui.Image` → PNG; `palette_generator` for color.
- No Firebase in this pass. Login = local stub.

Suggested structure:
```
lib/
  main.dart
  theme.dart
  models/entry.dart
  data/entry_store.dart          // Hive CRUD
  widgets/preference_card.dart   // the RepaintBoundary card + palette color
  screens/compose_screen.dart
  screens/card_screen.dart
  screens/archive_screen.dart
```

## Data model (one table)

```dart
class Entry {
  String id;
  String localPath;   // saved photo
  String text;        // the "I prefer ..." line (without the prefix)
  DateTime createdAt;
}
```

## Voice (copy matters as much as visuals)

Lowercase, observational, specific. e.g. "ferns that uncurl like a slow question",
"a flat white before the world wakes up". Empty states invite action, errors explain
plainly — never twee.

## v2 (later — do NOT build now)

AI enhancement as the paid tier: free = plain-photo card, subscription = AI-enhanced.
Three candidate routes (full repaint / enhance-not-replace / background-only); the
"enhance-not-replace" route is the one to test first. Before any code, validate by
hand: run a few real snapshots through an off-the-shelf image AI and see which output
the owner would actually post. That answer decides the approach.
