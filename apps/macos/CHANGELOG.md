# Changes – Minutes

## Unreleased

### New
- **Import a recording:** make a session from an existing audio or video file. Click **Import a recording…** on the New session tab or in the menu of the menu bar icon, or drop files on the popover. The app copies the file, keeps the video for screen frames and starts the transcription at once. The original file stays where it is. For more files, the app asks: one session with parts or separate sessions. ffmpeg adds mkv, webm, ogg, opus and other formats ([ADR-0034](../../docs/adr/0034-import-existing-recordings.md)).
- Settings → Recording: **Keep the video of imported files**.
- **Copy a summary:** the copy button in the Outputs list puts the summary on the clipboard. Mail, Teams, Word and Pages paste formatted text with headings, lists and tables. Text editors paste the Markdown. Right-click has **Copy as Markdown text** and **Share…**.
- **Drag a summary** from the Outputs list to Mail, Slack or Finder.
- **Copy the transcript** with the copy button in the Transcript card.
- **Show prompt** in the Summary card opens the full text that the model gets: the system prompt and the task from the template, the detail, the language and Extra.

### Changed
- **Settings:** a new **Models** tab has OpenCode, Claude and Codex. The **Summary** tab has the defaults, the templates, the system prompt and the screen frames. The window is larger.
- **Offer OpenCode for summaries:** you can turn OpenCode off, the same as Claude and Codex. A new summary then starts with the first tool that is on.
- One note "Where the data goes" applies to all models. A cloud provider in OpenCode gets the transcript the same as Claude or Codex.
- Settings no longer show the status of the OpenCode agent. The app syncs it before each summary.
- **The same settings for all tools:** OpenCode, Claude and Codex have the same rows: the switch, **Program** with the path that the app found, the default model and **Advanced** with an own path. The Model picker shows only the tools that are on, without the "(cloud)" label.
- **Removed:** the OpenCode agent name. OpenCode always uses the agent `meeting-summary` with the system prompt of the app.

## 1.2.0 – 2026-11-17

### New
- **Audio only:** turn off the Screen switch on the New session tab. The app records system audio and the microphone without a video ([ADR-0032](../../docs/adr/0032-audio-only-recording.md)).
- **Menu of the menu bar icon:** a right click or a Control-click opens a menu with Start or Stop recording, Stop transcription, Stop writing minutes, Settings and Quit ([ADR-0033](../../docs/adr/0033-menu-bar-icon-context-menu.md)).

## 1.1.0 – 2026-11-17

### New
- **Continue recording:** a stopped or interrupted session gets a new part. Start it from the session detail, the session list, a banner on the New session tab or the notification after an unexpected stop.
- **Merge with previous session:** two sessions of one meeting become one session with one transcript and one summary. Finished part transcripts are reused.
- The session detail and the list show the number of parts and an interrupted recording.
- **Updates:** the app checks for a new version once a day and installs it with one click (Sparkle, [ADR-0031](../../docs/adr/0031-app-updates-sparkle.md)). A blue dot next to the menu bar icon and a row in the popover show a new version. The app does not restart during a recording or a job. Settings → General turns the checks and the automatic install on or off. Version 1.0.0 has no updater: install this version manually one time.
- **Open source in About:** links to the source code, the release notes of the running version, the user guide and a problem report with the app and macOS versions filled in.

### Safety and reliability
- Video and audio are written with movie fragments every 10 seconds. After a crash or a power loss, the recording stays readable ([ADR-0030](../../docs/adr/0030-crash-resilient-recording.md)).
- The app stops the recording correctly before it quits, before a restart or a shut down of the Mac, and before sleep.
- At launch, the app repairs interrupted sessions and resets a transcription that a crash stopped.

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
