# App controls

Sources: brief (kept locally), feedback from Henrich (2026-11-13) · Updated: 2026-11-13

Decisions: [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md), [ADR-0014](../../docs/adr/0014-sessions-tab-cleanup-editor.md).

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

## Session states

Recording → Preparing audio → Transcription → Waiting for summary → Summary → Done / Error.

You can repeat each step without a new recording. "Transcribed" does not mean "checked".

## Sessions tab

- A list of all sessions with their size on disk and their state (transcript, summary).
- A click opens the session detail. Right-click: Open, Finder, Free up space, Delete session.
- **Free up space in all sessions:** deletes the video, audio and frames. The transcript and the summaries stay.
- **Delete session:** moves the whole folder to the Trash.
- The confirmation is directly in the popover. An alert would close the popover.

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

## About

Settings has an About tab: icon, the name Minutes, version, tagline, a short workflow in 4 steps, and links to the app data and the sessions. See [ADR-0019](../../docs/adr/0019-product-name-minutes.md).

## UI language

The UI is in English (default) or in Slovak. Select the language in Settings → General → App language. It applies after a restart. The Slovak translation is in `Localizable.xcstrings`. See [ADR-0018](../../docs/adr/0018-ui-localization-english-default.md).

## Settings

See the table in [ADR-0012](../../docs/adr/0012-menu-bar-ui-and-settings.md#settings-separate-window).
