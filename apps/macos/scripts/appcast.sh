#!/usr/bin/env bash
# Adds the current version to the update feed apps/site/appcast.xml (Sparkle, ADR-0031).
#
# Order of a release:
#   1. apps/macos/scripts/release.sh           -> build/release/Minutes-<version>.dmg
#   2. Create the GitHub release v<version> with the .dmg (gh release create ...).
#   3. apps/macos/scripts/appcast.sh           -> signs the .dmg and adds the appcast item
#   4. Commit apps/site/appcast.xml and push it to main. The Pages workflow publishes it.
#
# The script refuses to run when the .dmg is not downloadable from GitHub yet, so the appcast never
# announces a version that the app cannot download.
#
# One-time setup: generate the EdDSA key pair with Sparkle `generate_keys` (in the Sparkle package,
# bin/generate_keys). The private key stays in your Keychain. Back it up with `generate_keys -x <file>`
# to a safe place outside the repository. Put the public key in SPARKLE_PUBLIC_ED_KEY in project.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
APPCAST="$REPO_ROOT/apps/site/appcast.xml"
cd "$ROOT"

VERSION="$(grep -E '^\s+MARKETING_VERSION:' project.yml | awk '{print $2}')"
BUILD="$(grep -E '^\s+CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}')"
DMG="$ROOT/build/release/Minutes-$VERSION.dmg"
URL="https://github.com/softverse-space/minutes/releases/download/v$VERSION/Minutes-$VERSION.dmg"

[[ -f "$DMG" ]] || { echo "Missing $DMG. Run scripts/release.sh first." >&2; exit 1; }

SIGN_UPDATE="$(find "$ROOT/build" -path '*/artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1)"
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update not found. Run: xcodebuild -resolvePackageDependencies -project OfflineMeetingSummary.xcodeproj -scheme OfflineMeetingSummary -derivedDataPath build/DerivedData" >&2
  exit 1
fi

echo "==> Check that GitHub serves the .dmg"
if ! curl -sfIL -o /dev/null "$URL"; then
  echo "GitHub does not serve $URL yet. Create the GitHub release v$VERSION with the .dmg first." >&2
  exit 1
fi

echo "==> Sign Minutes $VERSION (build $BUILD)"
# Output: sparkle:edSignature="..." length="..."
SIGNED="$("$SIGN_UPDATE" "$DMG")"
SIGNATURE="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<<"$SIGNED")"
LENGTH="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<<"$SIGNED")"
[[ -n "$SIGNATURE" && -n "$LENGTH" ]] || { echo "sign_update gave no signature: $SIGNED" >&2; exit 1; }

python3 -I "$ROOT/scripts/appcast_item.py" "$APPCAST" "$ROOT/CHANGELOG.md" "$VERSION" "$BUILD" "$URL" "$SIGNATURE" "$LENGTH"
echo "==> Done. Commit apps/site/appcast.xml and push it to main."
