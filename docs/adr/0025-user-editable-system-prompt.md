# ADR-0025: The user edits a copy of the system prompt

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0015](0015-system-prompt-in-app.md)

## Context

ADR-0015 put the system prompt only in the app bundle. A user could change it only in the repository and with a new build. The "Show" button in Settings opened a temporary copy in the default app for `.md`. On some Macs this app is Xcode, and nothing visible happened.

Users want to change the summary rules without a new build.

## Options

1. **Keep the prompt only in the bundle** – one version for all users. A user cannot change the rules.
2. **Edit the prompt in a text field in Settings** – no file. But a long Markdown text is hard to edit in a small field.
3. **A copy in Application Support, edited in the user's editor** – the app copies the default prompt at start. The summary uses the copy. The user edits it in any editor.

## Decision

We select option 3.

- The app copies `prompts/meeting-summary.md` from the bundle to `~/Library/Application Support/OfflineMeetingSummary/prompts/meeting-summary.md`.
- All models use the copy: OpenCode (through the agent), Claude and Codex. When the copy is missing or empty, the app uses the default from the bundle.
- The app stores a digest of the default that it wrote last time. At start, it replaces the copy with a new default only when the copy is missing, empty or equal to that last default. Thus an edited copy stays, and an unedited copy gets updates.
- Settings → Summary shows if the copy is edited. "Edit" opens the copy in the editor from Settings → General. The menu has "Show in Finder" and "Reset to default…".
- The OpenCode agent follows the copy. The app writes the agent at start, before each summary and after "Update agent", as ADR-0015 says.
- The default prompt stays in `apps/macos/prompts/meeting-summary.md`. We change the default there.

## Consequences

- A user can change the summary rules without a new build.
- A user with an edited copy does not get a new default automatically. "Reset to default…" gives the new default, but the user's changes are lost.
- Bad rules in an edited copy can make summaries worse. The user can reset the copy at any time.
- The frame tool permissions do not depend on the prompt. The OpenCode agent settings come from `OpenCodeAgent` in the code (ADR-0023), not from the copy.
