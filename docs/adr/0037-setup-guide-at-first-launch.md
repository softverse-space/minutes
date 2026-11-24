# ADR-0037: Setup guide at the first launch

- **Status:** Proposed
- **Date:** 2026-11-24
- **Decided by:** Henrich Neuschl

## Context

A new user must do several things before the first minutes: allow Screen & System Audio Recording, allow the microphone, download the transcription model and turn on a summary tool. These settings are in different places: the popover, System Settings and four Settings tabs. A new user does not know the order and must search for them.

## Options

1. **Banners in the popover only** – no new window, but the popover is small and closes when the user goes to System Settings.
2. **A step-by-step wizard with Next and Back** – clear order, but more screens, and the user cannot skip a step easily.
3. **One window with a checklist** – all steps on one page. Each step shows its state and one action. The window stays open while the user goes to System Settings.

## Decision

We take option 3.

- The window "Welcome to Minutes" opens by itself one time, at the first launch. The key `setupGuideShown` in UserDefaults records it.
- A user of an older version who has a transcription model already does not get the window. The app sets the key without the window.
- The steps: 1. Screen & System Audio Recording. 2. Microphone. 3. Transcription model (download with progress). 4. Tool for the summary (switches for OpenCode, Claude and Codex, and whether the app finds the program). Optional: ffmpeg.
- A done step shows a green check mark. The window updates the states when the app becomes active again.
- The menu of the menu bar icon has **Setup guide…**. It opens the window again.

## Consequences

- The model download is in two places: the guide and Settings → Transcription. Both use `WhisperKitEngine.download`.
- The screen permission needs a restart of the app. The step says it.
- The website screenshots do not show the guide. Add a screenshot when the website describes the first launch.
