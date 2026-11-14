# ADR-0013: Project structure – XcodeGen and the OMSCore package

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

Mainly agents work on the app. Agents cannot easily read the `.xcodeproj` file, and changes to it cause conflicts. We want to test the logic without UI quickly from the terminal.

## Decision

- XcodeGen generates the Xcode project from `app/macos/project.yml`. The `.xcodeproj` is not in git.
- The logic without UI and without system APIs is in the local Swift package `app/macos/OMSCore` (templates, transcript, prompt, session). Tests: `swift test` (Swift Testing).
- The app (`app/macos/OfflineMeetingSummary`) contains the UI, ScreenCaptureKit, WhisperKit, OpenCode and Keychain.
- The build copies the templates, the agent and `frame-at.sh` into the app from `app/templates`, `app/opencode` and `app/scripts`. Phase 0 and the app have one source.
- Signing: ad-hoc by default (`Config/App.xcconfig`). A local `Config/Signing.xcconfig` (not in git) can set Apple Development or Developer ID Softverse ([ADR-0011](0011-distribution-signed-dmg.md)).
- Dependency: WhisperKit `exactVersion: 1.1.1`.

## Consequences

- Build: `xcodegen generate && xcodebuild -scheme OfflineMeetingSummary build`.
- With ad-hoc signing, macOS asks for the screen recording permission again after each build.
