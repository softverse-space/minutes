# ADR-0021: First release 1.0.0 – file name, version and packaging

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0019](0019-product-name-minutes.md) (app file), extends [ADR-0011](0011-distribution-signed-dmg.md)

## Context

Before the first distribution to colleagues, we must decide the app file name, the version and the procedure for signing, notarization and the `.dmg`. ADR-0019 postponed the rename of the `OfflineMeetingSummary.app` file to the first distribution. It also expected a change of the bundle ID.

## Options

1. **Rename the file and the bundle ID** – everything has the name Minutes. The data, the settings and the Keychain key need a migration. The user allows screen recording again.
2. **Rename only the file** (`PRODUCT_NAME = Minutes`) – the user sees Minutes everywhere. The bundle ID `sk.softverse.OfflineMeetingSummary`, the data and the Keychain stay. The user does not see the bundle ID.

## Decision

We select option 2.

- The app file is `Minutes.app`. The bundle ID, the data path (`~/Library/Application Support/OfflineMeetingSummary`) and the Keychain service do not change.
- The first version is **1.0.0** (build 1).
- The script `app/scripts/release.sh` makes the release:
  1. an archive in the Release configuration, signed with Developer ID Application (the team from `Signing.xcconfig`) and a timestamp,
  2. export (`developer-id`) and signature check,
  3. a signed `.dmg` with a link to Applications,
  4. notarization through `notarytool` with a profile in Keychain, and `stapler`,
  5. a SHA-256 checksum.
- The author creates the notarization profile (`minutes-notary`) once. The password is never in the repository or in the script.
- The script deletes the intermediate `.app` copies when it is done. A second app with the same bundle ID could take the screen recording permission.

## Consequences

- The name of the project, scheme and target in Xcode stays `OfflineMeetingSummary`. The user does not see it.
- The release build has a different signature (Developer ID) than the development build (Apple Development). Thus macOS asks for the screen recording permission again at the first start of the release build.
- Updates are manual through a new `.dmg` for now. Sparkle stays in phase 2.
