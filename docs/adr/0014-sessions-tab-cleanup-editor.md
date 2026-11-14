# ADR-0014: Sessions tab, deletion, freeing space and the summary editor

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0012](0012-menu-bar-ui-and-settings.md)

## Context

Feedback after the first test: the list of recent sessions below the Start button will grow too long. The user wants to delete a session and free space from old recordings. The user wants to open summaries in Visual Studio Code.

## Decision

1. **Tabs in the popover:** "New session" (screen selection, audio, Start) and "Sessions" (all sessions, size, actions). After Stop, the session detail opens on the Sessions tab.
2. **Delete session:** the app moves the full session folder to the Trash. The session also disappears from the app. The confirmation is directly in the popover (an alert would close the popover).
3. **Free space:** for one session or for all sessions. The app deletes the video, the audio (`audio/`, `*.wav`, `*.m4a`) and the frames (`frames/`). The transcript, the summaries and `session.json` stay. The deletion time is in `session.json` (`mediaRemovedAt`). You cannot transcribe such a session again.
4. **Editor:** the setting General → "Open transcripts and summaries with". The default is Visual Studio Code if it is installed, otherwise the default system app. It applies to `.md`, `.txt`, `.srt`, `.vtt`, `.json`.

## Consequences

- You can restore a deleted session from the Trash. You cannot undo the action that frees space.
- The automatic video deletion after N days (ADR-0012) stays. It deletes only the video.
