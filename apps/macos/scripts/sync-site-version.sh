#!/usr/bin/env bash
# Shows the released version on the website and in the README (release step, see
# .claude/skills/release/SKILL.md). Run it only after the GitHub release v<version> exists.
#
# Usage: apps/macos/scripts/sync-site-version.sh
#   The new version comes from project.yml. The old version comes from the README badge.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
SITE=apps/site/index.html
README=README.md

NEW="$(sed -nE 's/^[[:space:]]+MARKETING_VERSION:[[:space:]]*([0-9.]+).*/\1/p' apps/macos/project.yml | head -1)"
OLD="$(sed -nE 's/.*badge\/version-([0-9.]+)-.*/\1/p' "$README" | head -1)"
[[ -n "$OLD" ]] || { echo "No version badge in $README." >&2; exit 1; }
if [[ "$OLD" == "$NEW" ]]; then echo "The site and the README already show $NEW."; exit 0; fi

# Only these places show the current version. Sentences such as "From version 1.1.0, ..." stay.
O="${OLD//./\\.}"
sed -i '' -E \
  -e "s/Minutes-$O\.dmg/Minutes-$NEW.dmg/g" \
  -e "s/(Download Minutes|Stiahnuť Minutes) $O/\1 $NEW/g" \
  -e "s/(version|verzia) $O<\/div>/\1 $NEW<\/div>/g" \
  -e "s/(· version|· verzia) $O'/\1 $NEW'/g" \
  -e "s/(open source · version|open source · verzia) $O/\1 $NEW/g" \
  -e "s/<h2>Minutes $O<\/h2>/<h2>Minutes $NEW<\/h2>/g" \
  "$SITE"
sed -i '' -E \
  -e "s/badge\/version-$O-/badge\/version-$NEW-/g" \
  -e "s/Minutes-$O\.dmg/Minutes-$NEW.dmg/g" \
  -e "s/Download Minutes $O/Download Minutes $NEW/g" \
  "$README"

echo "Changed $OLD -> $NEW in $SITE and $README."
echo "Check the places that still name $OLD. Most are history and stay:"
grep -n "$O" "$SITE" "$README" || true
