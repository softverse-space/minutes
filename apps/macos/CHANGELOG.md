# Changes – Minutes

## 1.0.0 – 2026-11-14

First release for colleagues.

### New
- App in the Mac menu bar: records the screen, the system audio and the microphone.
- Transcript locally (WhisperKit) or through a server with an OpenAI-compatible API. SK, CS, EN and their mix.
- Summary by a template (standard or custom instruction) through any model in OpenCode. Optionally Claude or Codex for meetings that are not sensitive.
- Custom templates in the templates folder, for example a company summary format.
- Sessions tab: search, free up space, delete a session.
- UI in English (default) and Slovak. Set the app language in Settings → General.
- The menu bar icon shows the status: recording, transcript progress, summary writing, summary done.
- App icon with light, dark and tinted appearance.
- About tab and a guide with screenshots (`apps/site/index.html`).
- About tab shows the licenses of Minutes and of WhisperKit.

### Safety and reliability
- The model can run only the frame tool with a time, and only for the current session. OpenCode, Claude and Codex get narrower permissions ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md)).
- Cancel stops the model process and its child processes.
- Cancel shows "Cancelling…" at once and turns off the button. A transcription that waits for the model load stops at once; the load continues in the background for the next transcription. After a cancel, the session shows that the job was cancelled.
- The app stops a recording when the video cannot be written or the disk is almost full. The audio stays.
- One session runs one operation at a time: recording, transcription, summary or freeing space.
- Transcription through a server sends one part at a time. A damaged audio file gives an error, not a short transcript.

### Known limitations
- The summary through OpenCode with the app's agent needs OpenCode 2 or later. The app checks the agent permissions before each summary and does not start when it cannot check them.
- Updates are manual for now, with a new `.dmg`.
- On the first start of the release build, macOS asks again for the screen recording permission.
