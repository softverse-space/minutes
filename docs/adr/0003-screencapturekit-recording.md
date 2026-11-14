# ADR-0003: Recording with ScreenCaptureKit and separate audio tracks

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

We record the selected screen, the system audio (Teams, Meet, Zoom) and the microphone. Today OBS does this.

## Options

1. **ScreenCaptureKit** – `SCShareableContent` for the list of screens for a custom selection with previews ([ADR-0012](0012-menu-bar-ui-and-settings.md)), `capturesAudio` for system audio, `captureMicrophone` for the microphone (macOS 15+), writing with `SCRecordingOutput` or `AVAssetWriter`.
2. **AVCaptureScreenInput** – old API, no system audio.
3. **Control OBS through WebSocket** – dependency on OBS.

## Decision

ScreenCaptureKit. Video goes to `recording.mov` (H.264, default 5 fps). Each audio source goes to its own AAC file: `audio/system.m4a` and `audio/mic.m4a`. The app fills gaps in the audio with silence, so that the time matches the video. The app saves the offset of the first sample against the video in `session.json`.

Verified 2026-11-13: 8 s test, video 1280×720, system audio stereo 48 kHz, microphone mono 48 kHz, track offset below 0.4 s.

## Consequences

- Two tracks give low-cost diarization: microphone track = "me", system track = "others".
- The video can have a low frame rate (for example 2–5 fps). This is sufficient for presentations, and the file is small.
- The app needs the Screen Recording and Microphone permissions.
- Verify: behavior when the monitor changes, when the Mac goes to sleep and in long meetings (2+ h).
