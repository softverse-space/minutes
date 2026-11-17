#!/usr/bin/env bash
# Builds a signed and notarized Minutes .dmg for distribution (ADR-0011, ADR-0021).
#
# Usage:
#   apps/macos/scripts/release.sh                  # build, sign, notarize, staple
#   apps/macos/scripts/release.sh --skip-notarize  # build and sign only (local test)
#
# One-time setup for notarization (you enter the app-specific password yourself):
#   xcrun notarytool store-credentials minutes-notary --apple-id <apple-id> --team-id <TEAM_ID>
#
# The script reads the Apple team ID from TEAM_ID or from DEVELOPMENT_TEAM in
# apps/macos/Config/Signing.xcconfig (not in git). See Signing.xcconfig.example.
#
# Output: apps/macos/build/release/Minutes-<version>.dmg and its .sha256 file.
#
# After the GitHub release exists, run scripts/appcast.sh to announce the update (ADR-0031).
set -euo pipefail

SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-minutes-notary}"
NOTARIZE=1
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
WORK="$OUT/work"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cd "$ROOT"
if [[ -z "${TEAM_ID:-}" && -f Config/Signing.xcconfig ]]; then
  TEAM_ID="$(sed -nE 's|^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*|\1|p' Config/Signing.xcconfig | tail -1)"
fi
if [[ -z "${TEAM_ID:-}" ]]; then
  echo "TEAM_ID is not set. Set DEVELOPMENT_TEAM in Config/Signing.xcconfig or run: TEAM_ID=<TEAM_ID> $0" >&2
  exit 1
fi
VERSION="$(grep -E '^\s+MARKETING_VERSION:' project.yml | awk '{print $2}')"
DMG="$OUT/Minutes-$VERSION.dmg"

# A distributed build without the public key can never update itself (ADR-0031).
ED_KEY="$(sed -nE 's/^[[:space:]]+SPARKLE_PUBLIC_ED_KEY:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/p' project.yml | head -1)"
if [[ -z "$ED_KEY" && $NOTARIZE == 1 ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY in project.yml is empty. Run Sparkle generate_keys and set the public key (see scripts/appcast.sh)." >&2
  exit 1
fi

echo "==> Minutes $VERSION"
rm -rf "$WORK" "$DMG" "$DMG.sha256"
mkdir -p "$WORK"

# Removes intermediate copies of the app. A second app with the same bundle ID
# can take over the Screen Recording permission of the development build.
cleanup() {
  for app in "$WORK/Minutes.xcarchive/Products/Applications/Minutes.app" "$WORK/export/Minutes.app" "$WORK/dmg/Minutes.app"; do
    [[ -d "$app" ]] && "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Generate project"
xcodegen generate >/dev/null

echo "==> Archive (Release, $SIGN_IDENTITY)"
xcodebuild -project OfflineMeetingSummary.xcodeproj -scheme OfflineMeetingSummary -configuration Release \
  -derivedDataPath "$WORK/DerivedData" -archivePath "$WORK/Minutes.xcarchive" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive | grep -E "error:|warning: .*sign|ARCHIVE (SUCCEEDED|FAILED)"

echo "==> Export"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>$SIGN_IDENTITY</string>
  <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$WORK/Minutes.xcarchive" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" | grep -E "error:|EXPORT (SUCCEEDED|FAILED)"

APP="$WORK/export/Minutes.app"
echo "==> Verify signature"
codesign --verify --deep --strict --verbose=1 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority=Developer ID|TeamIdentifier|Runtime"
echo "==> Update feed: $(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")"

echo "==> Build .dmg"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Minutes.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "Minutes $VERSION" -srcfolder "$WORK/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  echo "==> Notarize (profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "==> Notarization skipped. Do not distribute this .dmg."
fi

# Only the file name in the checksum file: it goes public with the release, and a full path shows the local home folder.
(cd "$(dirname "$DMG")" && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "==> Done: $DMG"
