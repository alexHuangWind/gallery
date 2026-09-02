#!/usr/bin/env bash
#
# One-time iOS bootstrap. This is what generated the `ios/` folder that is now
# checked into the repo — kept here as the record of how it was produced, not
# as a script meant to run again.
#
# DO NOT re-run this against the checked-in project. `flutter create` rewrites
# Runner.xcodeproj/project.pbxproj from scratch, which drops things this
# script cannot re-add for you: `Runner/Runner.entitlements` (Sign in with
# Apple), the `CODE_SIGN_ENTITLEMENTS` reference to it, and `DEVELOPMENT_TEAM`.
# Losing any of those silently breaks Apple sign-in the next time someone
# builds. If `ios/` ever needs to be regenerated for real, redo those three
# things by hand afterwards — see `ios/Runner/Runner.entitlements` and the
# team id in `tool/README.md`.
#
# What it did: generated the Xcode project with the real Flutter tool
# (correct by construction; hand-writing project.pbxproj's UUIDs is not),
# then added the things `flutter create` does NOT know about — the
# permission usage strings iOS requires (a missing one is a hard crash, not
# a denial) — and wired plugins.

set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="ios/Runner/Info.plist"
PB="/usr/libexec/PlistBuddy"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "iOS setup needs macOS with Xcode. Run this on your Mac." >&2
  exit 1
fi

echo "==> generating iOS platform files"
flutter create --platforms=ios --org com.iprefer --project-name iprefer .

set_string() {
  local key="$1" value="$2"
  if $PB -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    $PB -c "Set :$key $value" "$PLIST"
  else
    $PB -c "Add :$key string $value" "$PLIST"
  fi
  echo "    $key"
}

echo "==> setting the name shown under the app icon"
# flutter create derives this from the project name and produces "Iprefer",
# which reads as a typo and disagrees with Android's "I prefer". The phrase
# keeps its capital wherever it is the app's name; the lowercase voice is for
# what the app says, not what it is called.
set_string CFBundleDisplayName "I prefer"

echo "==> adding permission usage strings to Info.plist"

# Location. We only ever ask for when-in-use — there is no background tracking.
set_string NSLocationWhenInUseUsageDescription \
  "Marks where you were when you recorded something you liked, so it can find you again there."

# image_picker.
set_string NSCameraUsageDescription \
  "Takes the photo of the thing you like."
set_string NSPhotoLibraryUsageDescription \
  "Chooses a photo of something you like."
set_string NSPhotoLibraryAddUsageDescription \
  "Saves your finished card to your photos."

echo "==> generating plugin wiring"
# On a Flutter with Swift Package Manager enabled (3.44+ default) this writes
# ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage and there
# is no Podfile at all. On an older CocoaPods-mode Flutter it writes the
# Podfile instead — handled below.
flutter pub get
flutter build ios --config-only --no-codesign

if [[ -f ios/Podfile ]]; then
  echo "==> pinning the iOS deployment target (CocoaPods mode)"
  # 13.0 is Flutter's own minimum (3.44 era); geolocator and flutter_map
  # need 12.0 or newer, so the Flutter floor satisfies them too.
  if grep -q "^platform :ios" ios/Podfile; then
    sed -i '' "s/^platform :ios.*/platform :ios, '13.0'/" ios/Podfile
  elif grep -q "^# platform :ios" ios/Podfile; then
    sed -i '' "s/^# platform :ios.*/platform :ios, '13.0'/" ios/Podfile
  else
    printf "platform :ios, '13.0'\n%s" "$(cat ios/Podfile)" > ios/Podfile
  fi
  echo "    ios/Podfile -> 13.0"

  echo "==> installing pods"
  # CocoaPods crashes outright in a non-UTF-8 shell (Encoding::CompatibilityError).
  (cd ios && LANG=en_US.UTF-8 pod install)
else
  echo "==> no Podfile: plugins are wired through Swift Package Manager; nothing to pin or install"
fi

echo
echo "done. now run:  flutter run -d ios"
