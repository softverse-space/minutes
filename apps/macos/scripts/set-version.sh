#!/usr/bin/env bash
# Prepares a new version in the source (release step 1, see .claude/skills/release/SKILL.md).
#
# Usage: apps/macos/scripts/set-version.sh <version> [<date>]
#   - sets MARKETING_VERSION in project.yml,
#   - increases CURRENT_PROJECT_VERSION by 1 (Sparkle compares the build number, ADR-0031),
#   - renames "## Unreleased" in CHANGELOG.md to "## <version> – <date>".
#
# The website and the README keep the published version. scripts/sync-site-version.sh changes
# them after the GitHub release exists.
set -euo pipefail

NEW="${1:?Usage: set-version.sh <version> [<date>]}"
DATE="${2:-$(date +%F)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must be X.Y.Z, not '$NEW'." >&2; exit 1; }
OLD="$(sed -nE 's/^[[:space:]]+MARKETING_VERSION:[[:space:]]*([0-9.]+).*/\1/p' project.yml | head -1)"
BUILD="$(sed -nE 's/^[[:space:]]+CURRENT_PROJECT_VERSION:[[:space:]]*([0-9]+).*/\1/p' project.yml | head -1)"
NEXT_BUILD=$((BUILD + 1))

newest="$(printf '%s\n%s\n' "$OLD" "$NEW" | sort -V | tail -1)"
[[ "$NEW" != "$OLD" && "$newest" == "$NEW" ]] || { echo "$NEW is not higher than $OLD." >&2; exit 1; }
grep -q '^## Unreleased$' CHANGELOG.md || { echo "CHANGELOG.md has no '## Unreleased' section. Add the changes first." >&2; exit 1; }

sed -i '' -E "s/^([[:space:]]+MARKETING_VERSION:[[:space:]]*)[0-9.]+/\1$NEW/" project.yml
sed -i '' -E "s/^([[:space:]]+CURRENT_PROJECT_VERSION:[[:space:]]*)[0-9]+/\1$NEXT_BUILD/" project.yml
sed -i '' "s/^## Unreleased$/## $NEW – $DATE/" CHANGELOG.md

echo "Version $OLD (build $BUILD) -> $NEW (build $NEXT_BUILD). CHANGELOG section: $NEW – $DATE."
