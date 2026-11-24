# App controls

Sources: brief (kept locally), feedback from Henrich (2026-11-13), [continue and merge request](../raw/2026-11-17-continue-and-merge-sessions.md), [app updates](../../docs/specs/app-updates.md), [import request](../raw/2026-11-18-import-recordings.md), UI review (2026-11-22) · Updated: 2026-11-22

Decisions: [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md), [ADR-0014](../../docs/adr/0014-sessions-tab-cleanup-editor.md), [ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md), [ADR-0030](../../docs/adr/0030-crash-resilient-recording.md), [ADR-0032](../../docs/adr/0032-audio-only-recording.md), [ADR-0033](../../docs/adr/0033-menu-bar-icon-context-menu.md), [ADR-0034](../../docs/adr/0034-import-existing-recordings.md), [ADR-0035](../../docs/adr/0035-settings-tabs-and-model-data-note.md), [ADR-0036](../../docs/adr/0036-session-detail-result-first-and-shared-styles.md).

The popover has two tabs: **New session** and **Sessions**. The recent sessions are no longer below the Start button.

The app runs in the background, without a Dock icon. You control it only through the menu bar icon.

```
 ┌───────────────────────────────┐      ┌───────────────────────────────┐
 │ Select a screen               │      │ ● Recording       00:42:17    │
 │ ┌─────────┐ ┌─────────┐       │      │ Screen: DELL U2723            │
 │ │ ▓▓▓▓▓▓▓ │ │ ░░░░░░░ │       │      │ 🎙 Microphone ▮▮▮▯▯  [on]     │
 │ │ Built-in│ │ DELL    │ ✓     │      │ 🔊 System     ▮▮▯▯▯  [on]     │
 │ └─────────┘ └─────────┘       │      │                               │
 │ 🎙 MacBook microphone ▮▮▯[on] │      │      [ ■ Stop session ]       │
 │ 🔊 System audio       ▮▯▯[on] │      └───────────────────────────────┘
 │                               │
 │      [ ● Start session ]      │      ┌───────────────────────────────┐
 │ Recent sessions · Settings    │      │ Session 13. 11. 10:30 (58 min)│
 └───────────────────────────────┘      │ Transcript: ✓ done            │
                                        │ Template: [Standard summary ▾]│
                                        │ Detail:  Brief|Medium|Detailed│
                                        │ Language: [Slovak ▾]          │
                                        │ Instruction: [              ] │
                                        │      [ Start summarizing ]    │
                                        └───────────────────────────────┘
```

## Audio only

The **Screen** section of the New session tab has a switch. When you turn it off, the app records only audio ([ADR-0032](../../docs/adr/0032-audio-only-recording.md)).

- The screen previews change to the note "Audio only". The recording view shows "Audio only" in place of the screen name.
- You must turn on system audio or the microphone. Else Start recording is not available.
- The app still needs the Screen Recording permission, because ScreenCaptureKit captures system audio only through it.
- The session has no `recording.mov`. The summary then has no frame tool.
- The app keeps the switch for the next sessions. Continue recording also uses it.

## Setup guide (ADR-0037)

- The window "Welcome to Minutes" opens one time, at the first launch of a new user. A user with a downloaded transcription model does not get it.
- One page with steps: Screen & System Audio Recording, Microphone, Transcription model, Tool for the summary. Optional: ffmpeg.
- Each step shows a number or a green check mark, a short help text and one action (**Allow**, **Download**, switches of the tools).
- The states update when the app becomes active again, for example after System Settings.
- **Setup guide…** in the menu of the menu bar icon opens the window again.

## Import a recording

- **Import a recording…** below Start recording on the New session tab, and in the menu of the menu bar icon, opens a file dialog.
- A drop of files on the popover also starts an import. The popover shows a dashed frame while you drag.
- More files: the app asks **One session** or **Separate sessions**. After a drop, the question is a panel on the New session tab. After the file dialog, it is an alert, because the popover is closed.
- A row above the bottom bar shows the running import with a progress bar, the percent done and **Cancel**. For ffmpeg files, the app gets the duration from ffprobe and reads `ffmpeg -progress`. Without ffprobe, the bar shows no percent.
- The list shows "Imported" for an imported session. The detail shows the name of the imported file. Continue recording is not available.
- Settings → Recording → **Keep the video of imported files** (default on).

## Session states

Recording → Preparing audio → Transcription → Waiting for summary → Summary → Done / Error.

You can repeat each step without a new recording. "Transcribed" does not mean "checked".

## Sessions tab

- A list of all sessions with their size on disk and their state (transcript, summary).
- A click opens the session detail. Right-click: Open, Finder, Free up space, Delete session.
- **Free up space in all sessions:** deletes the video, audio and frames. The transcript and the summaries stay.
- **Delete session:** moves the whole folder to the Trash.
- The confirmation is directly in the popover. An alert would close the popover.
- Right-click also has **Continue recording** and **Merge with previous session…**. The merge panel shows both sessions and the break.
- An interrupted session (crash or restart during the recording) has an orange icon.
- The row title is the topic of the summary. Without a summary it is "Meeting at 15:30".
- The row shows the screen name only when the sessions use more than one screen.
- VoiceOver reads the state of the session as text, not only as the color of the icon.

## Session detail

Decision: [ADR-0036](../../docs/adr/0036-session-detail-result-first-and-shared-styles.md).

- The title is the topic, the same as in the list. The date is below it.
- The result comes first: the Outputs card is above the Transcript and Summary cards.
- Each output row shows the topic, the version and the time. The file name is in the tooltip.
- With a summary, the Summary card is one row with **New summary…**. The form opens without a summary, while a summary job runs, after a failure, or after a click on **New summary…**. A new summary closes the form again.

## Popover styles

- Cards use `Card` with `Color.cardFill`. Banners and inline panels use `Banner` (info, warning, danger).
- Two corner radii: 8 pt for rows, tiles and fields, 12 pt for cards and banners (`Metrics`).
- Start recording and Stop recording are red. The blinking dot of the recording stays on with Reduce Motion.
- The microphone picker has its own row. **Import a recording…** is a small button below Start recording.
- The scroll views in the popover hide the scroll bar. The classic scroll bar (mouse, or "always show") is too heavy there.
- The summary form opens and closes without an animation. An animation resizes the popover frame by frame, and the popover flickers.

## Continue and merge

Specification: [continue-and-merge-sessions](../../docs/specs/continue-and-merge-sessions.md).

- **Continue recording** in the session detail records a new part into the same session. The recording view shows "Part N". The timer shows the time of the whole session.
- The New session tab shows a banner when the newest session stopped less than 30 minutes ago, or was interrupted less than 12 hours ago.
- After an unexpected stop (stream error, full disk, sleep, crash found at launch), the notification has the action **Continue recording**.
- A summary made before a merge or a continue has a clock icon in the outputs list.
- Before the app quits (also for a restart or a shut down of the Mac) and before sleep, the app stops the recording correctly.

## Opening and copying files

Transcripts and summaries open in the app that you select in Settings → General. The default is Visual Studio Code.

- **Copy a summary:** the copy button in a row of the Outputs card. The clipboard gets the Markdown, HTML and RTF. Mail, Teams, Word and Pages paste formatted text. Text editors paste the Markdown. `MarkdownHTML` in OMSCore makes the HTML.
- Right-click on a summary: Open, Copy, **Copy as Markdown text** (only the Markdown), **Share…**, Show in Finder.
- **Drag** a summary row to Mail, Slack or Finder. The file moves as an attachment.
- **Copy the transcript:** the copy button in the Transcript card. The clipboard gets the Markdown text.

## Prompt preview

**Show prompt** below Create summary opens the full text that the model gets with the current form. The file is in the temporary folder and opens in the editor from Settings → General. Changes in it have no effect.

The preview has three parts: the system prompt, the task (template, detail, language, date, parts, Extra, frame rules, output rules) and a line about the transcript with its word count. The preview does not copy the transcript.

## Menu bar icon

The icon is a circle with a sound wave (proposal C). `MenuBarIcon.swift` draws it. During transcription, the arc has a dot at its end, the same as the app icon ([ADR-0020](../../docs/adr/0020-app-icon-light-dark.md)).

| State | Icon |
|---|---|
| Idle | Circle with a wave |
| Recording | Red dot and time |
| Transcribing | The circle fills with the transcription progress of all tracks. The arc has a dot at its end |
| Writing summary | The arc spins. A spark is in the center |
| Summary is done | Spark and dot at the top right, until the user opens the popover |
| Update available | Idle icon and a small blue dot next to it, until the user looks at the update ([ADR-0031](../../docs/adr/0031-app-updates-sparkle.md)) |

## Menu of the menu bar icon

A left click opens the popover. A right click or a Control-click opens a menu ([ADR-0033](../../docs/adr/0033-menu-bar-icon-context-menu.md)):

- **Start recording** with the sources from the New session tab, or **Stop recording**.
- **Stop transcription** cancels the running transcription and the waiting ones.
- **Stop writing minutes** cancels all running summaries.
- **Settings…**, **Setup guide…** (ADR-0037) and **Quit Minutes**. A running recording stops correctly before the app quits.

When a start from the menu fails, the app posts a notification, because the popover is closed.

## About

Settings has an About tab: icon, the name Minutes, version, tagline, a short workflow in 4 steps, and links to the app data and the sessions. See [ADR-0019](../../docs/adr/0019-product-name-minutes.md).

The header has the link "Free and open source" and the button **Check for Updates…**. The section **Open source** links to the source code, the release notes of the running version, the user guide and a problem report on GitHub. The problem report gets only the app version, the macOS version and the Mac type ([ADR-0031](../../docs/adr/0031-app-updates-sparkle.md)).

## Updates

- A scheduled check that finds a new version shows a row "Minutes x.y.z is available" with **Update** above the popover footer, and the blue dot next to the menu bar icon.
- **Update** opens the Sparkle window: release notes, Install Update, Remind Me Later, Skip This Version.
- When a job runs, the popover shows "The update installs when the current job is done." The app restarts when no job runs.
- Settings → General → Updates: **Check for updates automatically** and **Download and install updates automatically**. In the Debug build, the switches and Check for Updates… are off, and a note says that this build does not check for updates.

## UI language

The UI is in English (default) or in Slovak. Select the language in Settings → General → App language. It applies after a restart. The Slovak translation is in `Localizable.xcstrings`. See [ADR-0018](../../docs/adr/0018-ui-localization-english-default.md).

## Settings

Tabs: General, Recording, Transcription, Summary, Models, About. The window is 640 pt wide. See [ADR-0035](../../docs/adr/0035-settings-tabs-and-model-data-note.md). It changes the table in [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md#settings-separate-window).

- **Summary:** what the summary contains. Defaults (template, detail, language), templates folder, system prompt, screen frames (ffmpeg status).
- **Models:** which tool writes the summary. One note "Where the data goes" for all tools, then OpenCode, Claude and Codex. Each tool has the same rows: the switch **Offer … for summaries** (OpenCode on, Claude and Codex off by default), **Program** with the path that the app found, the default model and **Advanced** with an own path. All rows are always visible. The default model is disabled while the tool is off. With an empty path, the app looks in /opt/homebrew/bin, /usr/local/bin, ~/.opencode/bin, ~/.local/bin, ~/.bun/bin and the PATH. When OpenCode is off, a new summary starts with the first tool that is on. The Model picker of the Summary card lists only the tools that are on. When all tools are off, the card shows a note and Create summary is disabled.
- The app syncs the OpenCode agent `meeting-summary` before each summary. Settings show no agent status and no agent name. OpenCode always uses this agent (ADR-0035).
