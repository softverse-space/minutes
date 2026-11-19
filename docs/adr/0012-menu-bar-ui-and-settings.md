# ADR-0012: Control through a menu bar popover and Settings

- **Status:** Accepted, amended by [ADR-0014](0014-sessions-tab-cleanup-editor.md) and [ADR-0035](0035-settings-tabs-and-model-data-note.md) (Settings tabs)
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The app runs in the background. It has no window in the Dock. The user controls everything through the menu bar icon (the top row of macOS).

## Decision

The app is `LSUIElement` (no Dock icon). A click on the icon opens a popover (`MenuBarExtra` with the `.window` style) with three states.

### 1. Idle state
- Previews of the current screens (`SCShareableContent`) with name and resolution. A click selects a screen. The app remembers the last choice.
- Audio switches: microphone (device selection) and system audio, with a level indicator.
- The **Start session** button.
- A link to recent sessions and to Settings.

### 2. Recording
- The menu bar icon shows that recording is active (red dot + time).
- Popover: elapsed time, the recorded screen, the active audio sources, the **Stop session** button.

### 3. After the session
- The **Start summarizing** button.
- Template: `standard`, custom templates, **Custom instruction** (text field).
- Detail level: **Brief / Medium / Detailed** (segmented control).
- Output language.
- An optional additional instruction.
- Step status: Audio preparation → Transcript → Summary → Done. On an error, a **Try again** button for that step.
- Done: a notification, the buttons **Open summary** and **Show in Finder**.

The transcription can start automatically right after Stop. The summary starts only after **Start summarizing**.

### Settings (separate window)

| Section | Items |
|---|---|
| Recording | sessions folder, video quality (fps, resolution), format, keep video after processing (yes / delete after N days) |
| Transcript | method: local / internal network; local engine and model; URL and model of the internal ASR; API key (Keychain); speech language: auto / sk / cs / en; start transcription automatically after Stop |
| Summary | path to `opencode`; model (`provider/model`); agent; default template, detail level and language; custom templates folder |
| General | start at login; keyboard shortcut for Start/Stop |

## Consequences

- We do not support selection of a window (instead of the full screen) yet. A screen is sufficient.
- The app writes audio source changes during recording to `session.json`.
