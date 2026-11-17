# Architecture

Sources: requirements (kept locally), brief (kept locally) · Updated: 2026-11-17

Decisions: [ADR-0002](../../docs/adr/0002-native-macos-menu-bar-app.md), [ADR-0003](../../docs/adr/0003-screencapturekit-recording.md), [ADR-0004](../../docs/adr/0004-local-transcription-engine.md), [ADR-0005](../../docs/adr/0005-llm-processing-via-opencode.md), [ADR-0010](../../docs/adr/0010-data-boundary-internal-asr.md), [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md), [ADR-0017](../../docs/adr/0017-model-choice-and-claude.md).

```
┌──────────────── Mac ────────────────────────────────────────────┐
│                                                                 │
│  Menu bar app (SwiftUI)                                         │
│   ├─ RecorderService ── ScreenCaptureKit ──► recording.mov      │
│   │                     (video + mic + system)                  │
│   ├─ AudioExtractor ─── ffmpeg ──► audio/mic.wav, system.wav    │
│   ├─ TranscriptionEngine                                        │
│   │    ├─ WhisperKitEngine (CoreML, default)                    │
│   │    ├─ ParakeetEngine (CoreML, candidate)                    │
│   │    └─ ServerAsrEngine (option) ──────────────┐ audio        │
│   │         ──► transcript.json / transcript.md                 │
│   ├─ FrameService ───── ffmpeg ──► frames/*.jpg                 │
│   └─ SummaryService ─── opencode run ───────────┐               │
│                                                 │               │
└─────────────────────────────────────────────────┼───────────────┘
                                                  │ text + frames (+ audio with ServerAsr)
                                                  ▼
               Model in OpenCode (local, server, cloud), Claude, Codex
```

## Components

| Component | Responsibility |
|---|---|
| `MenuBarController` | Icon, popover, state (idle / recording / processing), notifications. See [ui](ui.md) |
| `RecorderService` | List of screens with previews (`SCShareableContent`), recording, 2 audio tracks |
| `SessionStore` | Session folder and `session.json` ([ADR-0006](../../docs/adr/0006-session-folder-layout.md)) |
| `AudioExtractor` | Converts tracks to 16 kHz mono WAV |
| `TranscriptionEngine` | Protocol to swap the engine. Output: segments with time, speaker, language |
| `FrameService` | Keyframes at scene changes, a frame at time `t` |
| `SummaryService` | Builds the instruction from the template and runs `opencode run` or `claude -p`, as selected for the summary ([ADR-0017](../../docs/adr/0017-model-choice-and-claude.md)) |
| `OpenCodeAgent` (OMSCore) | Creates the OpenCode agent from the system prompt ([ADR-0015](../../docs/adr/0015-system-prompt-in-app.md)). `SystemPrompt` decides when the app updates the user's editable copy ([ADR-0025](../../docs/adr/0025-user-editable-system-prompt.md)). The agent denies everything except reads in the session folder and the exact frame command. `OpenCodePolicy` checks the rules that OpenCode resolves ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md)) |
| `ProcessRunner` (OMSCore) | Runs an engine CLI in its own process group. Cancel, a timeout and a too large output stop the whole group ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md)) |
| `SessionOperations` (OMSCore) | One operation for one session at a time: recording, transcription, summary, cleanup or merge ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md)) |
| Session parts (OMSCore) | `SessionPart`, `convertToParts`, `parts.tsv`, the combined transcript (`SessionParts.swift`, `SessionTranscripts.swift`) ([ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md)) |
| `SessionMerge` (OMSCore) | Moves the parts of a later session into an earlier one. A journal completes a merge that a crash interrupted |
| `SessionRecovery` (OMSCore) | At launch: gives an interrupted recording its end and its audio tracks, and resets a stuck transcription ([ADR-0030](../../docs/adr/0030-crash-resilient-recording.md)) |
| `AppDelegate` | Stops the recording correctly before the app quits |
| `TemplateStore` | Loads templates from `apps/macos/templates` and from Application Support |
| `Settings` | See [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md). API key in Keychain |

## Code

| Part | Where |
|---|---|
| Logic without UI (templates, transcript, prompt, session, storage, process runner, session operations) | `apps/macos/OMSCore` – tests `swift test` |
| UI and state | `apps/macos/OfflineMeetingSummary/App`, `UI` |
| Recording | `Recording/ScreenRecorder.swift`, `AudioTrackWriter.swift` (both with movie fragments, ADR-0030) |
| Transcription | `Transcription/` (WhisperKit, server with the OpenAI API, conversion to 16 kHz WAV) |
| Summary | `Summary/SummaryService.swift` (`opencode run`) |

XcodeGen generates the project from `apps/macos/project.yml` ([ADR-0013](../../docs/adr/0013-build-structure-xcodegen.md)).

## External tools

- `ffmpeg` (Homebrew)
- `whisper-cli` (Homebrew `whisper-cpp`) + model – phase 0 only. The app uses WhisperKit
- `opencode` with a configured provider; optionally `claude` and `codex`

Later the app can bundle ffmpeg and whisper. For now we take them from Homebrew.
