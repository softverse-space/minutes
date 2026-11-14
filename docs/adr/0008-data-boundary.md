# ADR-0008: Data boundary – what runs where

- **Status:** Superseded by ADR-0010
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

Recordings contain confidential information of customers and colleagues. They must not leave the Mac and the company network.

## Decision

| Step | Where it runs | What leaves the Mac |
|---|---|---|
| Recording | Mac | nothing |
| Audio and frame extraction | Mac (ffmpeg) | nothing |
| Transcription | Mac (local model) | nothing |
| Summary | internal model in the company through OpenCode | transcript text, selected frames |

- No third-party cloud service.
- The app sends no telemetry.
- Video and audio never leave the Mac.

## Consequences

- The "Summary" step needs the company network or VPN.
- If a sufficiently powerful local LLM becomes available later, the "Summary" step can run fully offline (new ADR).
