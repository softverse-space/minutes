# Changes – Minutes

What changed for you in each version. Short and for users: no internal details, no links to decisions or code.

## 1.3.1 – 2026-11-22

### Changed
- **Session detail:** your summaries are on top. **New summary…** opens the options for another summary. The title is the topic of the meeting.
- **Outputs:** each summary shows its topic and time instead of the long file name.
- **Sessions list:** a session without a summary shows its time, for example "Meeting at 15:30".
- **Recording:** Stop recording is red, the same as Start recording. The level meter is larger.
- **New session:** long microphone names are no longer cut.

### Reliability
- **Transcription model:** the app finds an incomplete WhisperKit download. Click **Download again** in Settings → Transcription.

## 1.3.0 – 2026-11-19

### New
- **Import a recording:** make minutes from an audio or video file that you already have. Click **Import a recording…** or drop the files on the popover. The original files stay where they are.
- **Copy a summary** with the copy button in the Outputs list. Mail, Teams and Word paste formatted text. You can also drag the summary to Mail, Slack or Finder.
- **Copy the transcript** with the copy button in the Transcript card.
- **Show prompt** in the Summary card shows the full text that the model gets.

### Changed
- **Settings:** a new **Models** tab has OpenCode, Claude and Codex, all with the same settings. The window is larger.
- You can turn OpenCode off, the same as Claude and Codex.

## 1.2.0 – 2026-11-17

### New
- **Audio only:** turn off the Screen switch on the New session tab. The app records only the system audio and the microphone.
- **Quick menu:** right-click the menu bar icon to start or stop a recording, stop a job, open Settings or quit.

## 1.1.0 – 2026-11-17

### New
- **Continue recording:** add a new part to a stopped or interrupted session.
- **Merge with previous session:** join two sessions of one meeting. You get one transcript and one summary.
- **Updates:** the app checks for a new version once a day and installs it with one click. It never restarts during a recording or a job. Version 1.0.0 has no updater: install this version manually one time.
- **About** has links to the source code, the release notes, the user guide and a problem report.

### Reliability
- A crash or a power loss no longer damages the recording.
- The app stops the recording correctly before it quits, before a restart and before sleep.
- At launch, the app repairs interrupted sessions.

## 1.0.0 – 2026-11-14

First release for colleagues.

### New
- The app lives in the Mac menu bar. It records the screen, the system audio and the microphone.
- Transcript on your Mac or through a transcription server. Slovak, Czech, English and their mix.
- Minutes by a template through any model in OpenCode. Optionally Claude or Codex for meetings that are not sensitive.
- Your own templates, for example your company's format.
- Sessions tab: search, free up space, delete a session.
- The app is in English and Slovak.
- The menu bar icon shows the status: recording, transcript, minutes.

### Reliability
- The model sees only the current session. It cannot run other commands.
- Cancel stops a job at once.
- The app stops a recording when the disk is almost full. The audio stays.

### Known limitations
- The summary through OpenCode needs OpenCode 2 or later.
- Updates are manual, with a new `.dmg`.
- On the first start, macOS asks for the screen recording permission.
