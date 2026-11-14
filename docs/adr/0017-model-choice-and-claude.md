# ADR-0017: Model choice for the summary and optional Claude

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl
- **Supersedes:** [ADR-0010](0010-data-boundary-internal-asr.md) (data boundary), amends [ADR-0005](0005-llm-processing-via-opencode.md)

## Context

OpenCode has more models in its configuration. The user could enter the model only as text in Settings. The user wants to select the model from a list and change it for a specific summary.

Some meetings are not sensitive. For these meetings, the user also wants to make the summary with Claude through the Claude Code CLI. ADR-0010 prohibited third-party cloud services.

## Options

1. **Only OpenCode, model selection from a list** – the data stays in the company. Claude is not available.
2. **Claude as a provider in OpenCode** – one tool. It needs an API key in the OpenCode configuration and mixes internal and cloud models in one list.
3. **Claude Code CLI as a second engine, optional for each summary** – uses the existing `claude` login. The cloud is clearly separate.

## Decision

Option 3.

- The app gets the list of OpenCode models from the `opencode models` command. The default model is in Settings → Summary.
- For each summary, the user selects the engine and the model: the internal model (OpenCode) or Claude Sonnet, Opus or Haiku.
- Claude shows only after the user enables it in Settings (default: disabled).
- Each session starts with the default internal model. The Claude choice does not carry over to the next session.
- When the user selects Claude, the UI shows that the transcript and the frames go to the cloud.
- Claude runs as `claude -p` with the app's system prompt. The prompt and the transcript go through stdin. The only tools are `Read` and `Bash` limited to `frame-at.sh`. MCP servers and slash commands are disabled.

Data boundary:

| Step | Where it runs | What leaves the Mac |
|---|---|---|
| Recording | Mac | nothing |
| Audio and frame extraction | Mac | nothing |
| Transcript – local (default) | Mac | nothing |
| Transcript – internal network (option) | internal ASR | audio (WAV) |
| Summary – internal model (default) | OpenCode, internal gateway | transcript text, selected frames |
| Summary – Claude (option for each summary) | Anthropic (cloud) | transcript text, selected frames |

- Video never leaves the Mac. No telemetry.

## Consequences

- The user is responsible for the decision whether a meeting is sensitive, for each summary.
- Claude Code loads the user's global settings (for example `~/.claude/CLAUDE.md`, hooks). This affects the output style.
- `opencode models` also returns models that are not for text (ASR, TTS). The app does not filter them yet.
