# ADR-0019: Product name Minutes and the app icon

- **Status:** Accepted, icon superseded by [ADR-0020](0020-app-icon-light-dark.md), app file amended by [ADR-0021](0021-first-release-packaging.md)
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

"Offline Meeting Summary" is a description, not a brand. It is long, and "offline" is not always true now: the transcription can go through the internal network and the summary optionally through Claude ([ADR-0017](0017-model-choice-and-claude.md)). The app had no icon of its own.

The app name is also in the bundle ID, in the data path (`~/Library/Application Support/OfflineMeetingSummary`) and in the Keychain service. macOS binds the screen recording permission to the bundle ID and the signature.

## Options

1. **Change only the display name** (`CFBundleDisplayName`, `CFBundleName`) – the user sees "Minutes". The permissions, the data and the Keychain key stay. The app file and the bundle ID have the old name.
2. **Change also `PRODUCT_NAME` and the bundle ID** – the name is the same everywhere. The user must allow screen recording again. The data and the Keychain key need a migration.

## Decision

We select option 1.

- The product name is **Minutes**. Slogan: "Meeting minutes that stay on your local machine."
- `PRODUCT_NAME`, the bundle ID `sk.softverse.OfflineMeetingSummary`, the data path and the Keychain service do not change.
- App icon (variant C3e): indigo background, two coral speech bubbles and a white card. The card shows a sound wave and, below it, checked tasks. The icon shows the input (speech) and the output (tasks). The source is `app/design/app-icon.svg`. The PNG files are in `Resources/Assets.xcassets/AppIcon.appiconset`.
- Settings has an **About** tab: icon, name, version, slogan, short procedure and links to the data.
- The guide for colleagues is in `site/index.html`, with screenshots in `site/images/`.

## Consequences

- The app file is still `OfflineMeetingSummary.app`. Rename it together with the bundle ID at the first distribution (.dmg, [ADR-0011](0011-distribution-signed-dmg.md)). Then migrate the data and the Keychain key.
- We did not check trademarks and the name "Minutes" in the App Store. Check them before public distribution.
- The repository and its folders have the old name.
