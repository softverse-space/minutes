# ADR-0002: Native macOS menu bar app in Swift/SwiftUI

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The user wants an icon in the menu bar: Start session, screen selection, Stop, processing. [ADR-0012](0012-menu-bar-ui-and-settings.md) describes the UI in detail. The app runs only on a Mac (Apple Silicon). Screen and audio recording needs system APIs and permissions.

## Options

1. **Swift + SwiftUI (`MenuBarExtra`)** – direct access to ScreenCaptureKit, AVFoundation and CoreML. Small app, low resource use. macOS only.
2. **Tauri / Electron** – web UI. Recording would still need a native module in Swift. Larger app.
3. **Script + OBS** – the current state. Many manual steps.

## Decision

We propose option 1. The minimum system version is macOS 15 (because of `captureMicrophone` and `SCRecordingOutput`).

## Consequences

- We need Xcode and code signing ([ADR-0011](0011-distribution-signed-dmg.md)).
- The app runs processing (ffmpeg, whisper, opencode) as external processes. Thus we can also test the logic from the phase 0 script.
