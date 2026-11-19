# ADR-0035: Settings tabs and one data note for all models

- **Status:** Proposed
- **Date:** 2026-11-19
- **Decided by:** Henrich Neuschl

## Context

The Summary tab of Settings mixed three topics: the content of the summary, the summary tools and the data boundary. Examples:

- The **System prompt** section showed the ffmpeg status of video frames.
- The **OpenCode** section showed the agent `meeting-summary` with a sync status and an Update button. The app syncs the agent before each summary, so the status had no use. The user edits the system prompt in its own section.
- Only Claude and Codex had a cloud warning. OpenCode can also send the transcript to a cloud provider (Anthropic, OpenAI, Google and others).
- The window was narrow (540 pt), and the long texts were hard to read.

ADR-0012 defines the sections of Settings. This ADR changes that table.

## Options

1. **Keep one Summary tab and reorder its sections** – fewer tabs, but the tab stays long.
2. **Split it into Summary and Models** – each tab has one topic. One more tab.

## Decision

Option 2.

| Tab | Sections |
|---|---|
| General | launch at login, app language, updates, sessions folder, app to open files, privacy |
| Recording | video (fps, width), old videos (delete after N days), notice to participants |
| Transcription | method, speech language, automatic start, local model or server |
| Summary | defaults (template, detail, language), templates folder, system prompt, screen frames (ffmpeg) |
| Models | where the data goes, then one section for each tool (OpenCode, Claude, Codex) with the same rows: switch, program (found path or "Not found"), default model, advanced (own path). All rows are always visible; the default model is disabled while the tool is off |
| About | version, workflow, open source links |

- **One data note** at the top of Models applies to all tools: the transcript and frames go to the provider of the model. A local model keeps them on the Mac. A cloud provider gets them, also through OpenCode. So no tool has the label "(cloud)" in Settings or in the Model picker. The footer of Claude and Codex says that they always send the data to their cloud.
- Each tool has the switch **Offer … for summaries**. OpenCode is on by default, Claude and Codex are off. When OpenCode is off, a new summary starts with the first tool that is on. The Model picker of the Summary card lists only the tools that are on. When all tools are off, Models shows a warning, the Summary card shows a note instead of the picker, and Create summary is disabled.
- The footer of Claude and Codex only says that they always run in the cloud.
- The agent status row and the agent name setting are removed. OpenCode always uses the app agent `meeting-summary`, which the app writes from the system prompt before each summary. So all three tools get the same system prompt and have the same settings. The old key `opencodeAgent` is no longer read; a custom agent name from an earlier version is ignored.
- The window is 640 pt wide and at least 600 pt high.

## Consequences

- One new setting key: `opencodeEnabled` (default on). Existing values stay.
- The warning in the Summary card of a session still shows only for Claude and Codex. The app cannot know if an OpenCode provider is local. The data note in Models covers this case.
- The website screenshot of Settings → Summary must be made again at the next release.
