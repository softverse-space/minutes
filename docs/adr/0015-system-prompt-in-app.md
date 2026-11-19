# ADR-0015: The system prompt is part of the app

- **Status:** Accepted, amended by [ADR-0035](0035-settings-tabs-and-model-data-note.md) (no custom agent name)
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The rules for the summary were in the OpenCode agent file `app/opencode/agent/meeting-summary.md`. The app copied it to `~/.config/opencode/agent/` only once, when the file was not there yet. Thus a new version of the prompt did not get to the user. A colleague had to copy the agent manually.

Also, the rules do not belong to OpenCode. If we change the model provider in the future, the rules must stay the same.

## Options

1. **Agent in `~/.config/opencode/agent/`, copied only once** – the current state. New versions do not get to the user.
2. **A separate configuration through the `OPENCODE_CONFIG_DIR` variable** – does not change the user's configuration. But `opencode run` connects to a background service, which possibly does not see the variable. The agent is not available in interactive OpenCode.
3. **A provider-independent prompt in the app and an adapter for OpenCode** – the app creates the agent from the prompt at startup and before each summary, when it is different. The agent also works in interactive OpenCode.

## Decision

We select option 3.

- The system prompt is in `app/prompts/meeting-summary.md`. It contains only the text of the rules, without provider settings.
- The prompt is an app resource (`Contents/Resources/prompts/`).
- `OpenCodeAgent` in `OMSCore` adds the OpenCode settings to the prompt: tools, permissions and temperature.
- The app writes `~/.config/opencode/agent/meeting-summary.md` at startup, before each summary and after a click on "Update agent". It writes the file only when the content is different.
- In the future, a different provider gets the same prompt as a system message through its own adapter.

This decision changes the part of ADR-0005 about the location of the `meeting-summary` agent.

## Consequences

- A colleague installs the app and the agent is immediately up to date. The colleague copies nothing manually.
- The app owns the `meeting-summary` agent file. It overwrites manual changes in it. Set up a custom agent under a different name.
- The script `app/scripts/process-session.sh` uses the agent that the app installed.
- We change the prompt only in `app/prompts/meeting-summary.md` and release a new version of the app.
