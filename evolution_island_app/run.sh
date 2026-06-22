#!/usr/bin/env bash
# Convenience launcher for 达尔文进化岛.
# Any arguments are forwarded to `flutter run` (e.g. ./run.sh -d chrome).
set -e
cd "$(dirname "$0")"

# Generate the platform folders (web/android/ios/desktop) if they are missing.
# This is idempotent and only writes the boilerplate runners, never lib/.
if [ ! -d "web" ] && [ ! -d "android" ] && [ ! -d "macos" ]; then
  flutter create . --project-name evolution_island >/dev/null
fi

flutter pub get
flutter run "$@"
