# App controls

Sources: brief (kept locally), feedback from Henrich (2026-11-13), [continue and merge request](../raw/2026-11-17-continue-and-merge-sessions.md), [app updates](../../docs/specs/app-updates.md), [import request](../raw/2026-11-18-import-recordings.md) · Updated: 2026-11-18

Decisions: [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md), [ADR-0014](../../docs/adr/0014-sessions-tab-cleanup-editor.md), [ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md), [ADR-0030](../../docs/adr/0030-crash-resilient-recording.md), [ADR-0032](../../docs/adr/0032-audio-only-recording.md), [ADR-0033](../../docs/adr/0033-menu-bar-icon-context-menu.md), [ADR-0034](../../docs/adr/0034-import-existing-recordings.md).

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

## Import a recording

- **Import a recording…** below Start recording on the New session tab, and in the menu of the menu bar icon, opens a file dialog.
- A drop of files on the popover also starts an import. The popover shows a dashed frame while you drag.
- More files: the app asks **One session** or **Separate sessions**. After a drop, the question is a panel on the New session tab. After the file dialog, it is an alert, because the popover is closed.
- A row above the bottom bar shows the running import with progress and **Cancel**.
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

## Continue and merge

Specification: [continue-and-merge-sessions](../../docs/specs/continue-and-merge-sessions.md).

- **Continue recording** in the session detail records a new part into the same session. The recording view shows "Part N". The timer shows the time of the whole session.
- The New session tab shows a banner when the newest session stopped less than 30 minutes ago, or was interrupted less than 12 hours ago.
- After an unexpected stop (stream error, full disk, sleep, crash found at launch), the notification has the action **Continue recording**.
- A summary made before a merge or a continue has a clock icon in the outputs list.
- Before the app quits (also for a restart or a shut down of the Mac) and before sleep, the app stops the recording correctly.

## Opening files

Transcripts and summaries open in the app that you select in Settings → General. The default is Visual Studio Code.

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
- **Settings…** and **Quit Minutes**. A running recording stops correctly before the app quits.

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

See the table in [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md#settings-separate-window).
