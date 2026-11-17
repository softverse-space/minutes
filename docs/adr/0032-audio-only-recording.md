# ADR-0032: Audio-only recording

- **Status:** Proposed
- **Date:** 2026-11-17
- **Decided by:** Henrich Neuschl

## Context

Each session records a video of the screen ([ADR-0003](0003-screencapturekit-recording.md)). Many meetings have no shared screen, for example a phone call or a talk in a room. The video then only uses disk space. The user wants to record only audio.

## Options

1. **A switch on the New session tab, the recorder keeps ScreenCaptureKit** – the stream still captures system audio and the microphone. It asks for very small frames (64 px wide, 1 per second) and writes no video. One code path for both modes. The Screen Recording permission is still necessary.
2. **A second recorder without ScreenCaptureKit** – `AVAudioEngine` for the microphone and a Core Audio process tap for system audio (macOS 14.4+). No Screen Recording permission for the microphone. But two recorders to maintain, and the tap needs its own permission.
3. **Record the video and delete it after Stop** – no code change in the recorder. But the app writes the large file anyway, and a crash leaves it on disk.

## Decision

Option 1.

- `AppSettings.captureScreen` (default `true`). The **Screen** section of the New session tab has a switch for it. The app keeps the value for the next sessions.
- In the audio-only mode, the recorder uses the main display only for the capture filter. It ignores the frames.
- The timeline starts at the first audio sample of any track, in place of the first video frame. The offsets in `session.json` are relative to this start.
- `session.json` has no `video` and no `displayName`. The code already treats a missing video as normal: recovery, merge, parts and the summary (no frame tool).
- Start recording needs at least one audio source in this mode.

## Consequences

- An audio-only session is much smaller. At the default settings (5 fps, 1920 px), the video alone is about 7 MB per minute.
- The minutes cannot use pictures of the screen.
- The app still needs the Screen Recording permission, also for a recording with only the microphone. Option 2 can remove this later.
- A session can have parts with a video and parts without a video. The part map lists only parts with a video, so the frame tool works for them.
- Verify: a long audio-only recording (2+ h), the offset between the two tracks, continue of an audio-only session.
