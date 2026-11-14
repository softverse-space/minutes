# ADR-0010: Data boundary – optional transcription through the internal network

- **Status:** Superseded by [ADR-0017](0017-model-choice-and-claude.md)
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl
- **Supersedes:** [ADR-0008](0008-data-boundary.md)

## Context

ADR-0008 allowed transcription only on the Mac. The internal gateway (LiteLLM) offers a transcription model. The user decided that the app can also offer transcription through the internal network.

## Decision

| Step | Where it runs | What leaves the Mac |
|---|---|---|
| Recording | Mac | nothing |
| Audio and frame extraction | Mac (ffmpeg / AVFoundation) | nothing |
| Transcription – **local** (default) | Mac | nothing |
| Transcription – **internal network** (option) | internal ASR (LiteLLM) | audio (WAV) |
| Summary | internal model through OpenCode | transcript text, selected frames |

- The default is local transcription. The user turns on transcription through the internal network in Settings.
- Video never leaves the Mac.
- No third-party cloud service. No telemetry. Logs do not contain meeting content.
- The API key for the internal ASR is in the macOS Keychain. The app does not write it to files.

## Consequences

- When the user selects "internal network", the UI clearly shows that audio leaves the Mac.
- Internal transcription needs the company network or VPN.
- We must verify that the internal endpoint returns segments with times (`verbose_json`).
