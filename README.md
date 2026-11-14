<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="apps/site/images/app-icon-dark.png">
  <img src="apps/site/images/app-icon-light.png" width="128" height="128" alt="Minutes app icon">
</picture>

# Minutes

**Meeting minutes that stay on your local machine.**

A macOS menu bar app. It records a meeting, transcribes the speech locally and writes the minutes from a template.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-15173d) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2B-15173d) ![Swift](https://img.shields.io/badge/Swift-SwiftUI-ff6b4a) ![version](https://img.shields.io/badge/version-1.0.0-ffb347) ![license](https://img.shields.io/badge/license-Apache--2.0-15173d)

[User guide](apps/site/index.html) · [Changelog](apps/macos/CHANGELOG.md) · [Decisions (ADR)](docs/adr/README.md)

</div>

<p align="center">
  <img src="apps/site/images/popover-new-session.png" width="32%" alt="New session: select a screen and audio sources">
  <img src="apps/site/images/popover-session.png" width="32%" alt="Session detail: transcript and minutes">
  <img src="apps/site/images/popover-sessions.png" width="32%" alt="List of sessions">
</p>

## How it works

1. **Record.** In the menu bar, select a screen, system audio (Teams, Meet, Zoom) and your microphone. Click **Start recording**.
2. **Transcribe.** When you stop, a local model (WhisperKit) transcribes each audio track separately and adds time stamps. Slovak, Czech, English and a mix of them.
3. **Write the minutes.** Select a template, a detail level, a model and a language. A model of your choice writes the minutes in Markdown: any model in OpenCode (local, self-hosted or cloud), or Claude or Codex. When it needs to see the screen, it cuts a frame from the video.

Each meeting gets its own folder with video, audio, transcript and minutes. The menu bar icon shows when a recording runs, how far the transcription is and when the minutes are done.

The app UI is in English (default) and Slovak. The minutes can be in Slovak, English, Czech or German.

## Privacy

| Data | Where it stays |
|---|---|
| Video | always on your Mac |
| Audio | on your Mac; goes to a transcription server (OpenAI-compatible API) only if you select one |
| Transcript and selected frames | go to the model you set up in OpenCode – with a local model they stay on your Mac; to Claude (Anthropic) or Codex (OpenAI) only if you turn them on and select them for a specific summary |
| Telemetry | none |

Details: [ADR-0008](docs/adr/0008-data-boundary.md), [ADR-0017](docs/adr/0017-model-choice-and-claude.md).

## Install

Requirements: Apple Silicon Mac, macOS 15 or later, about 3 GB of disk space, [OpenCode](https://opencode.ai) 2 or later with a model of your choice.

1. Open `Minutes-1.0.0.dmg` and move Minutes to Applications.
2. Open Minutes and allow screen recording (System Settings → Privacy & Security → Screen & System Audio Recording).
3. In Settings → Transcription, click **Download model**.
4. Install OpenCode and set up a model, for example a local one with Ollama: `brew install opencode ffmpeg`.
5. Optional: install Claude Code or Codex and turn them on in Settings → Summary.

Full guide: [apps/site/index.html](apps/site/index.html#install).

## Build from source

Requirements: Xcode 26 or later (the app icon is an Icon Composer `.icon` file), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd apps/macos
xcodegen generate
xcodebuild -scheme OfflineMeetingSummary -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Minutes.app
```

Logic tests: `cd apps/macos/OMSCore && swift test`.

For stable macOS permissions between builds, copy `apps/macos/Config/Signing.xcconfig.example` to `Signing.xcconfig` and fill in your team. `apps/macos/scripts/release.sh` makes a release: Developer ID signature, notarization and `.dmg`. See [apps/macos/README.md](apps/macos/README.md#release).

## Repository layout

| Folder | Content |
|---|---|
| [`apps/`](apps/) | One folder for each app. A Linux or Windows version gets its own folder here |
| [`apps/macos/`](apps/macos/) | The macOS app (SwiftUI) and the `OMSCore` logic package |
| [`apps/macos/templates/`](apps/macos/templates/) | Summary templates and detail levels |
| [`apps/macos/prompts/`](apps/macos/prompts/) | System prompt for the minutes |
| [`apps/macos/design/`](apps/macos/design/) | App icon generator |
| [`apps/macos/scripts/`](apps/macos/scripts/) | Release and helper scripts |
| [`apps/site/`](apps/site/) | User guide (one HTML page, English and Slovak, works offline) |
| [`docs/adr/`](docs/adr/) | Architecture Decision Records |
| [`wiki/`](wiki/) | Project wiki |

## Contributing

- Write everything in the repository in English: code, identifiers, commit messages, documentation, ADRs and the wiki. Slovak is only a translation of the UI and the website.
- Record each architectural decision as an ADR with the [template](docs/adr/0000-template.md).
- Write UI texts in English and add the Slovak translation to `Localizable.xcstrings`.
- Never commit recordings, transcripts of real meetings or API keys.

Rules for AI agents are in [AGENTS.md](AGENTS.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE) ([ADR-0026](docs/adr/0026-apache-2-license.md)). The license does not include the name "Minutes", the name "Softverse" and the app icon.

---

<sub>Minutes · Softverse, spol. s r. o. · original working name: Offline Meeting Summary ([ADR-0019](docs/adr/0019-product-name-minutes.md))</sub>
