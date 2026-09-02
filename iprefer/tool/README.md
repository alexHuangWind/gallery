# tool/

Scripts that build, sign, and ship iPrefer. Two families: getting the iOS
project to exist at all (`setup_ios.sh`), and getting a built app onto a
phone or into TestFlight (`asc_profile.mjs`, `testflight.sh`,
`install_device.sh`). Plus a couple of one-off generators.

## Credentials

Everything here authenticates as an **App Store Connect API key**, read
straight off this machine — nothing secret is checked into the repo:

```
~/.appstoreconnect/issuer_id
~/.appstoreconnect/private_keys/AuthKey_WUD39Q6XN3.p8
```

That key id (`WUD39Q6XN3`) is hardcoded in `asc_profile.mjs` and
`testflight.sh`. It has no cloud-managed-certificate access, which is why
these scripts mint provisioning profiles via the API and sign with
`xcodebuild -exportArchive` manually rather than via
`-allowProvisioningUpdates`.

Two other ids are hardcoded across these scripts and the checked-in iOS
project, rather than looked up:

- **Team id** `R7D4C52VX8` — in `testflight.sh`, `install_device.sh`
  (both in the generated `exportOptionsPlist`), and
  `ios/Runner.xcodeproj/project.pbxproj` (`DEVELOPMENT_TEAM`).
- **Bundle id** `com.iprefer.iprefer` — in `asc_profile.mjs`,
  `testflight.sh`, `install_device.sh`, the Xcode project, and
  `server/.dev.vars` / `server/src/apple.ts` (`APPLE_AUDIENCE`, since the
  bundle id is what Apple puts in a native app's identity token `aud`).

## The pipeline

- **`setup_ios.sh`** — one-time bootstrap that generated the checked-in
  `ios/` folder and added the permission usage strings and iOS deployment
  target `flutter create` doesn't know about. Kept as the record of how
  `ios/` came to look the way it does, not meant to be re-run on this
  project — see the script's own header before touching it.

- **`asc_profile.mjs`** — ensures a provisioning profile exists for
  `com.iprefer.iprefer` and installs it locally, printing its name for the
  export step. Two modes:
  - default: an **App Store** profile, for TestFlight.
  - `--development`: a **development** profile that bakes in every iOS
    device currently `ENABLED` on the account, for a direct USB/Wi-Fi
    install. Re-mints itself if a device was registered after the profile
    was last built.

  Reuses an existing valid profile of the right name when one covers every
  needed device; otherwise deletes stale/invalid same-named profiles (Apple
  won't let two profiles share a name, and changing an App ID's capabilities
  invalidates every profile for it) and mints a fresh one against the
  matching certificate.

- **`testflight.sh`** — `flutter build ipa` for the archive only (its own
  signing attempt is left to fail, since this key can't cloud-sign), mints
  an App Store profile via `asc_profile.mjs`, exports a signed `.ipa` with
  `xcodebuild -exportArchive` (manual signing, `method: app-store-connect`),
  then uploads it with `xcrun altool`. Re-runnable.

- **`install_device.sh`** — same archive step, but mints a **development**
  profile (`asc_profile.mjs --development`), exports with
  `method: debugging` and the Apple Development certificate, then installs
  straight onto a paired device with `xcrun devicectl` and launches it. No
  App Store Connect upload. Takes an optional device UDID; otherwise picks
  the first paired iPhone/iPad `devicectl` sees.

- **`icon/generate_icon.dart`** — renders the app icon from the app's own
  italic serif glyph (not an AI image) and writes every iOS and Android
  size. Run as a widget test (`flutter test tool/icon/generate_icon.dart`)
  because that's the only harness here with a real Flutter engine and the
  bundled Playfair Display font.

- **`live_sync_check.dart`** — a wire-contract check: the real Dart sync
  client against a real running Worker (`cd server && npm run dev`, then
  `dart run tool/live_sync_check.dart`). Catches field-name or encoding
  mismatches between the Dart and TypeScript sides that a fake-backed unit
  test can't. Kept out of `test/` so `flutter test` never depends on a
  server being up.
