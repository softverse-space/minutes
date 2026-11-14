# ADR-0006: Session folder structure

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

Each recording has many outputs. We want them in one place and readable without the app. The current procedure already uses established file names (raw (kept locally)).

## Decision

We derive the names from the start time of the recording (`<timestamp>` = `YYYY-MM-DD_HH-MM-SS`).

```
<sessions folder>/<timestamp>/
  session.json                        # id, time and time zone, sources, engine, model, step status, audio source changes
  recording.mov                       # video + microphone track + system track (original, does not change)
  audio/mic.m4a, audio/system.m4a     # AAC per track (transcript with speaker me/others)
  <timestamp>_audio.wav               # phase 0 only: mixed tracks
  <timestamp>_transcript.txt|srt|vtt|json|md
  frames/                             # frames for verification
  outputs/<datum>_meetingsummary_<tema>.md
```

- The user sets the sessions folder and its location in the app ([ADR-0012](0012-menu-bar-ui-and-settings.md)).
- `<tema>` is 2–3 words without diacritics, with underscores, for example `sprint_planning`. The model proposes them. The user can change them.
- New processing does not overwrite older outputs. It adds a new file with the suffix `_v2`, `_v3`.

## Consequences

- The user can process a session again with a different template without a new transcript.
- The user can delete the video and keep the transcript and the summary.
