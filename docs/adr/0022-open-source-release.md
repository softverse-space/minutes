# ADR-0022: Public open-source repository, any model and Codex

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0005](0005-llm-processing-via-opencode.md), [ADR-0007](0007-output-templates.md), [ADR-0017](0017-model-choice-and-claude.md)

## Context

Minutes will be a public open-source project on GitHub. The app was tied to one company: an internal model through OpenCode, an internal transcription server address, a company summary template and internal sources in the wiki. The public code must not contain internal addresses, client names or company templates.

Before the publication, we did a code review by the Swift skills: SwiftUI, Swift Concurrency, architecture (SOLID) and tests.

## Options

1. **Keep the company defaults, only hide the addresses** – little work. Other people could not use the app.
2. **A provider-independent app** – the summary through any model in OpenCode, optionally Claude and Codex. A transcription server with an OpenAI-compatible API. The user enters the company settings.

## Decision

We select option 2.

**Summary engines**
- OpenCode is the default. It runs with the provider that the user sets up: a local model (for example Ollama), a company server or a cloud.
- Claude Code CLI and OpenAI Codex CLI are cloud engines. They are disabled by default. The user enables them in Settings → Summary. For these engines, the UI shows who gets the data (Anthropic, OpenAI).
- Codex runs through `codex exec` in a sandbox: `read-only`, or `workspace-write` only when the model may cut frames into the session folder. It does not create session files (`--ephemeral`).
- Each engine has its own `SummaryRunner` and model list (`opencode models`, `codex debug models`, Claude aliases). The user selects the default model of an engine in Settings → Summary from the list or enters it manually. Pure `EngineInvocation` functions in OMSCore make the CLI arguments, and tests cover them. A new engine does not change `SummaryService` or the model selection UI.

**Transcription through a server**
- The mode "Server (OpenAI-compatible API)" sends the audio to any `/v1/audio/transcriptions` endpoint. The address and the model have no default.
- The stored settings value `internal` stays valid, so that old settings continue to work.

**Repository content**
- The company template and the internal wiki sources are only in the `local/` folder, which git ignores. The user keeps the company template in the custom templates folder.
- The system prompt does not contain names of companies, clients or systems from real transcripts.
- The screenshots use fictional sample sessions.
- Before the first commit, we removed the names from the existing ADRs and wiki. This is an exception to the rule "do not rewrite ADRs": the history did not exist yet, and sensitive data must not be public.
- All repository content is in English. Slovak stays only as a UI and website translation.

**Code quality**
- The app compiles in Swift 6 mode with `SWIFT_STRICT_CONCURRENCY: complete` without warnings.
- Fixed review findings:
  - Transcriptions run one after another, and the app loads the WhisperKit model once.
  - The app reads the audio level without a block of the main thread (`Mutex`).
  - The recording stops in one block on the audio queue. Late samples no longer cause an exception.
  - Late progress messages do not overwrite the final job state.
  - The app changes `session.json` in one step (`updateMetadata`). Concurrent changes are not lost.
  - The sessions list, the sizes and the media deletion run outside the main thread. The UI does not read files during rendering.
  - `ProcessRunner` does not lose a cancellation and does not freeze when a subprocess keeps its output open.
  - A deletion from the sessions list needs a confirmation, the same as in the detail.
  - The icon buttons and the menu bar icon have VoiceOver labels.
  - The String Catalog has plural forms for counts (session, template, segment).
- The OMSCore tests are split by source file. They use temporary folders and remove them when done.

## Consequences

- Any person with a Mac can use the app. The user enters the company settings (model, server, templates).
- The author's local settings (address and model of the transcription server) are in the author's `UserDefaults`, not in the code.
- Next steps from the review that we postponed:
  1. Split `AppModel` into `RecordingController`, `JobCoordinator`, `SummaryFormState` and `SessionLibraryStore`.
  2. Give settings and system services (process, notifications, Keychain) through protocols instead of `AppSettings.current` and singletons.
  3. Add an app test target: `JobCoordinator`, `SummaryPipeline` with a fake process launcher, `AppSettings` from isolated `UserDefaults`.
  4. Use typed settings keys (`SettingKey<Value>`) instead of repeated strings and defaults.
  5. Move `protocol TranscriptionEngine`, the transcription results and the `multipart` body to OMSCore.
