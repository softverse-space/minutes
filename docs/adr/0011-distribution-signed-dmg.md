# ADR-0011: Distribution – signed app outside the App Store

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

Colleagues get the app directly from the author. We do not put it in the Mac App Store yet. macOS Gatekeeper blocks unsigned apps downloaded from the internet.

## Decision

- We sign the app with a **Developer ID Application** certificate and notarize it through Apple (`notarytool`).
- We distribute a `.dmg` with the app (through Teams, SharePoint or an internal website).
- Hardened Runtime is on. No App Sandbox (the app runs ffmpeg and opencode).
- The .dmg does not include models. The app downloads them at first start, with consent.

## Consequences

- We need the Apple Developer Program (company account) and a Developer ID certificate.
- Notarization sends only the app binary to Apple, not user data.
- Updates are manual for now (new .dmg). Maybe Sparkle later.
