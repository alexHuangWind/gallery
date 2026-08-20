#!/usr/bin/env bash
#
# Build, sign, and upload iPrefer to TestFlight.
#
#   ./tool/testflight.sh
#
# One-time prerequisites (done — kept here as the record):
#   - Bundle id com.iprefer.iprefer is registered as an App ID.
#   - App Store Connect app record exists (name "iPrefer — a taste diary",
#     appId 6803691574).
#
# Auth is the App Store Connect API key already on this machine — no Xcode
# account login required, nothing secret in this file:
#   key:    ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   issuer: ~/.appstoreconnect/issuer_id
#
# Signing note: this team's API key has no access to cloud-managed
# distribution certificates, so `xcodebuild -allowProvisioningUpdates` (auto
# cloud signing) fails with "Cloud signing permission error". Instead we mint
# an App Store provisioning profile against the existing Apple Distribution
# certificate via the API (tool/asc_profile.mjs) and sign MANUALLY. Re-runnable
# — the profile is reused if it already exists.
#
# Safe to re-run.

set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID="WUD39Q6XN3"
ISSUER_ID="$(tr -d '[:space:]' < "$HOME/.appstoreconnect/issuer_id")"
ARCHIVE="build/ios/archive/Runner.xcarchive"
IPA_DIR="build/ios/ipa"
EXPORT_PLIST="$(mktemp -t iprefer_export).plist"

echo "==> archiving"
# flutter's own IPA export attempts cloud signing and fails; we only need the
# archive it produces, so let that step fail without aborting the script.
flutter build ipa --export-method app-store || true
[[ -d "$ARCHIVE" ]] || { echo "no archive at $ARCHIVE" >&2; exit 1; }

echo "==> ensuring an App Store provisioning profile (API)"
PROFILE="$(node tool/asc_profile.mjs)"
echo "    profile: $PROFILE"

echo "==> exporting signed .ipa (manual signing)"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>export</string>
	<key>signingStyle</key><string>manual</string>
	<key>teamID</key><string>R7D4C52VX8</string>
	<key>signingCertificate</key><string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict><key>com.iprefer.iprefer</key><string>${PROFILE}</string></dict>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>stripSwiftSymbols</key><true/>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
rm -rf "$IPA_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$IPA_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

IPA="$(ls "$IPA_DIR"/*.ipa 2>/dev/null | head -1)"
[[ -n "${IPA:-}" ]] || { echo "export produced no .ipa" >&2; exit 1; }
echo "    exported: $IPA"

echo "==> uploading to TestFlight"
xcrun altool --upload-app --type ios \
  --file "$IPA" \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

echo
echo "done. the build processes in App Store Connect for ~5-15 min, then shows"
echo "under the app's TestFlight tab. Add it to internal testing and it lands"
echo "in the TestFlight app on your iPhone."
