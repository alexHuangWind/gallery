#!/usr/bin/env bash
#
# One-time iOS bootstrap. Run from the iprefer/ directory on a Mac with Xcode.
#
#   ./tool/setup_ios.sh
#
# Why a script instead of a checked-in ios/ folder: Runner.xcodeproj/project.pbxproj
# is a machine-generated file full of UUIDs. Generating it with the real Flutter
# tool is correct by construction; hand-writing it is not. This script generates
# it, then adds the things `flutter create` does NOT know about — the permission
# usage strings, which iOS requires (a missing one is a hard crash, not a denial).
#
# Safe to re-run: every edit below is idempotent.

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

echo "==> adding permission usage strings to Info.plist"
set_string() {
  local key="$1" value="$2"
  if $PB -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    $PB -c "Set :$key $value" "$PLIST"
  else
    $PB -c "Add :$key string $value" "$PLIST"
  fi
  echo "    $key"
}

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
