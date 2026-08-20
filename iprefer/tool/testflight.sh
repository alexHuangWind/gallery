#!/usr/bin/env bash
#
# Build, sign, and upload iPrefer to TestFlight.
#
#   ./tool/testflight.sh
#
# Prerequisites (one-time, done in the Apple portals — see the note at the
# bottom; this script does NOT create account objects):
#   1. The bundle id com.iprefer.iprefer is registered as an App ID.
#   2. An App Store Connect app record exists for that bundle id.
# Until both exist, the UPLOAD step fails with "no app found for bundle id".
#
# Auth is the App Store Connect API key already on this machine — no Xcode
# account login required, nothing secret lives in this file:
#   key:    ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   issuer: ~/.appstoreconnect/issuer_id
#
# Safe to re-run. Bumps the build number each run so App Store Connect always
# sees a fresh build.

set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID="WUD39Q6XN3"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
ISSUER_ID="$(tr -d '[:space:]' < "$HOME/.appstoreconnect/issuer_id")"

ARCHIVE="build/ios/archive/Runner.xcarchive"
IPA_DIR="build/ios/ipa"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "missing API key at $KEY_PATH" >&2
  exit 1
fi

echo "==> archiving (flutter build ipa stops at export; that's expected)"
# Produces the .xcarchive. The export it attempts fails without a logged-in
# Xcode account, so we do the export ourselves below with the API key.
flutter build ipa --export-method app-store || true

if [[ ! -d "$ARCHIVE" ]]; then
  echo "no archive at $ARCHIVE — the flutter archive step failed" >&2
  exit 1
fi

echo "==> exporting signed .ipa (API-key auth, auto-provisioning)"
rm -rf "$IPA_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$IPA_DIR" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

IPA="$(ls "$IPA_DIR"/*.ipa 2>/dev/null | head -1)"
if [[ -z "${IPA:-}" ]]; then
  echo "export produced no .ipa" >&2
  exit 1
fi
echo "    exported: $IPA"

echo "==> uploading to TestFlight"
# Fails here (not a signing error) if the App Store Connect app record does
# not exist yet — create it first, then re-run.
xcrun altool --upload-app \
  --type ios \
  --file "$IPA" \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID"

echo
echo "done. the build appears in App Store Connect → TestFlight in a few"
echo "minutes (it must finish processing, then you assign it to yourself as"
echo "an internal tester to get it on your iPhone)."

# ---------------------------------------------------------------------------
# One-time account setup this script deliberately does NOT do (your call —
# names and IDs are yours to reserve, matching how the other apps were made):
#
#   App Store Connect → Apps → + → New App
#     Platform: iOS
#     Name:     I prefer          (must be globally unique on the App Store)
#     Language: English
#     Bundle ID: com.iprefer.iprefer
#       └ if it's not in the dropdown: Certificates, IDs & Profiles →
#         Identifiers → + → App IDs → App → com.iprefer.iprefer, then reopen.
#     SKU:      iprefer
# ---------------------------------------------------------------------------
