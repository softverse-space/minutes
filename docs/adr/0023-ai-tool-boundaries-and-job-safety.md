# ADR-0023: Narrow AI tool permissions, process groups and one operation for one session

- **Status:** Accepted, amended by [ADR-0035](0035-settings-tabs-and-model-data-note.md) (no custom agent name)
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0005](0005-llm-processing-via-opencode.md), [ADR-0017](0017-model-choice-and-claude.md), [ADR-0022](0022-open-source-release.md)

## Context

A second code review before the public release found that some safety and concurrency statements in [ADR-0022](0022-open-source-release.md) were stronger than the code.

- A meeting transcript is not trusted input. It can contain text that tells the model to use its tools (prompt injection).
- The OpenCode agent denied only `edit`, `webfetch` and `bash`. The rule `"*frame-at.sh*": allow` matched every command that contains the script name. OpenCode 2.x allows every action by default, so web search, subagents and MCP tools stayed allowed.
- Claude had a general `Read` rule. Codex could write in the whole session folder. `frame-at.sh` accepted any folder and an unchecked time.
- Cancel sent SIGTERM only to the main process and returned a normal result. Child processes could continue.
- The video writer ignored its errors. The app continued to show a recording when the video no longer grew.
- Cleanup, transcription, summary and recording did not exclude each other. `updateMetadata` was a read–modify–write without a lock.

## Options

1. **Keep the script as a shell command, but make each boundary narrow** – small change, works with all three engines.
2. **Give the frame tool as an MCP server or a custom OpenCode tool** – no shell at all. It needs a server process and a different setup for each engine, and a global OpenCode tool is visible to all the user's agents.

## Decision

We select option 1. Option 2 stays possible later.

**Frame tool**
- `frame-at.sh <hh:mm:ss>` takes only a time. The session is the working folder, or its parent when the working folder is `frames`. The script checks the time format and writes only `frames/at_<time>.jpg`.

**OpenCode**
- The agent denies everything first (`"*": deny`). It then allows `read`, denies `external_directory` and allows only the exact frame command: the installed path in quotes and a time pattern `??:??:??`.
- The agent file uses the OpenCode 1.x `permission` syntax. OpenCode 2.x converts it; OpenCode 1.x ignores the 2.x syntax and would then allow everything. Checked with OpenCode 2.2.5.
- Before each summary with the managed agent, the app runs `opencode debug agents` and checks the whole resolved rule list (`OpenCodePolicy`). The list must have a rule that denies everything. Each rule after it must be a `deny` or one of the rules that the app wrote. Sample actions are only regression tests: a sample cannot find a rule such as `shell: python3 *`.
- The check fails closed. The summary starts only when the check succeeds. A timeout, a failed command, an unreadable output or a missing rule list stops the summary with a message. So the managed agent needs OpenCode 2.x. A custom agent that the user selects in Settings is the user's responsibility and has no check.

**Claude and Codex**
- Claude: the allow rules are `Read(<session>/frames/**)` and `Bash("<frame tool>":*)`. In `-p` mode Claude denies everything else that needs a permission.
- Codex: with frames, the sandbox is `workspace-write` and the workspace is only the `frames` folder. Without frames it is `read-only`.

**Processes**
- `ProcessRunner` is in OMSCore and uses `posix_spawn`. Each engine runs in its own process group.
- Cancel, a timeout and a too large output stop the whole group: SIGTERM, then SIGKILL after 3 seconds. A cancelled run throws `CancellationError`.
- The runner decides the result after it has read the output. A too large output is an error also when the process ends before the limit is found.
- stdout has a limit of 32 MB. stderr and the Codex progress output keep only the last 256 KB. A summary has a limit of 2 hours, a model list 30 seconds.

**Recording**
- The recorder reports a failed `startWriting`, a failed `append` and a failed writer status. The app then stops the recording.
- The app checks the free disk space every 5 seconds during a recording and stops below 300 MB.
- A video error does not discard the audio tracks.
- An error that the recorder reports during the start is kept and handled when the recording phase begins.

**Sessions**
- One operation for one session at a time: recording, transcription (also a waiting one), summary or cleanup. `SessionOperations` in OMSCore holds the rule. `AppModel` asks it on the main actor before each start. Deleting a session needs an idle session. Disabled buttons are only a hint.
- Cancel of a waiting transcription frees the session at once. It does not wait for the transcription that runs.
- Cancel during the WhisperKit model load stops the wait at once (`waitCancellably` in OMSCore). The load itself continues and stays cached, because the next transcription uses the same model.
- After a cancel, the UI shows "Cancelling…" and turns off the Cancel button until the job stops. Then the job has the state `cancelled`, and the session says that the job was cancelled.
- `updateMetadata` holds a process-wide lock for the read, the change and the write. The recording uses it too, and no longer keeps a copy of `session.json`.

## Consequences

- This decision corrects two statements of ADR-0022: concurrent metadata changes can no longer be lost, and Cancel now stops the engine and its children.
- OpenCode 1.x can no longer run the managed agent. The user must update OpenCode or select a custom agent.
- A user cannot transcribe again while a summary of the same session runs. Different sessions do not block each other.
- OMSCore now also has code that starts processes. Tests cover cancel, timeout, output limits, the frame tool input checks, the agent rules and the session rules (77 tests).
- Risks that we accept:
  - The user's own CLI configuration (Claude settings and hooks, Codex config, OpenCode global rules) is outside the app. Process arguments alone do not prove isolation. For OpenCode the app checks the result; for Claude and Codex it does not.
  - Claude can read the files in the session folder (its working folder). They are the transcript and the metadata, which the model gets anyway.
  - OpenCode 2.x can run the model in a background service. Cancel stops the `opencode run` client and its group. We did not verify that the service stops the model request.
  - A process that moves itself to another process group or session escapes the group signal.
  - The lock protects one app process. A second tool that writes `session.json` at the same time is not protected.
- Not verified: a real summary run with each engine after this change, and the recorder errors on a full disk. The app has no test target yet ([ADR-0022](0022-open-source-release.md), postponed step 3).
