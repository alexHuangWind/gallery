#!/usr/bin/env bash
#
# Build, sign for development, and install iPrefer straight onto a paired
# iPhone — no TestFlight round trip.
#
#   ./tool/install_device.sh            # first paired iPhone devicectl sees
#   ./tool/install_device.sh <udid>     # a specific one
#
# Shares the archive step and the API-minted-profile approach with
# tool/testflight.sh (see the signing note there). The difference is the
# profile: a development profile carries the registered device UDIDs and is
# signed with the Apple Development certificate, which is what lets the
# binary run outside the App Store. Re-runnable.

set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="build/ios/archive/Runner.xcarchive"
OUT_DIR="build/ios/device"
EXPORT_PLIST="$(mktemp -t iprefer_dev_export).plist"

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  # devicectl's own identifier (a CoreDevice UUID), not the UDID Xcode shows.
  DEVICE="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/iPhone|iPad/ && /paired/ {print $3; exit}')"
fi
[[ -n "$DEVICE" ]] || { echo "no paired iPhone/iPad visible to devicectl" >&2; exit 1; }
echo "==> target device: $DEVICE"

echo "==> archiving"
# flutter's own IPA export attempts cloud signing and fails; we only need the
# archive it produces, so let that step fail without aborting the script.
flutter build ipa --export-method app-store || true
[[ -d "$ARCHIVE" ]] || { echo "no archive at $ARCHIVE" >&2; exit 1; }

echo "==> ensuring a development provisioning profile (API)"
PROFILE="$(node tool/asc_profile.mjs --development)"
echo "    profile: $PROFILE"

echo "==> exporting a development-signed .ipa"
# exportArchive re-signs, so the archive's App Store signing is irrelevant
# here. "debugging" is what Xcode 15.4+ calls the old "development" method.
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>debugging</string>
	<key>destination</key><string>export</string>
	<key>signingStyle</key><string>manual</string>
	<key>teamID</key><string>R7D4C52VX8</string>
	<key>signingCertificate</key><string>Apple Development</string>
	<key>provisioningProfiles</key>
	<dict><key>com.iprefer.iprefer</key><string>${PROFILE}</string></dict>
	<key>compileBitcode</key><false/>
	<key>stripSwiftSymbols</key><true/>
	<key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
rm -rf "$OUT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

IPA="$(ls "$OUT_DIR"/*.ipa 2>/dev/null | head -1)"
[[ -n "${IPA:-}" ]] || { echo "export produced no .ipa" >&2; exit 1; }
echo "    exported: $IPA"

echo "==> installing on the phone"
xcrun devicectl device install app --device "$DEVICE" "$IPA"

echo "==> launching"
xcrun devicectl device process launch --device "$DEVICE" com.iprefer.iprefer || true

echo
echo "done. it's on the phone — the icon may take a second to appear."
