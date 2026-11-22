# Architecture Decision Records

Each decision is a separate file. [ADR-0001](0001-record-decisions-in-adr.md) gives the rules. Template: [0000-template.md](0000-template.md).

| ADR | Title | Status |
|---|---|---|
| [0001](0001-record-decisions-in-adr.md) | We record decisions as ADRs | Accepted |
| [0002](0002-native-macos-menu-bar-app.md) | Native macOS menu bar app in Swift/SwiftUI | Accepted |
| [0003](0003-screencapturekit-recording.md) | Recording with ScreenCaptureKit and separate audio tracks | Accepted |
| [0004](0004-local-transcription-engine.md) | Local transcription engine | Accepted |
| [0005](0005-llm-processing-via-opencode.md) | Transcript processing with OpenCode CLI and an internal model | Accepted, amended by 0015, 0017, 0022, 0023 |
| [0006](0006-session-folder-layout.md) | Session folder structure | Accepted, amended by 0029 (proposed) |
| [0007](0007-output-templates.md) | Templates, detail level and custom instruction | Accepted, amended by 0022 |
| [0008](0008-data-boundary.md) | Data boundary – what runs where | Superseded by 0010 |
| [0009](0009-llm-wiki.md) | LLM wiki as project memory | Accepted |
| [0010](0010-data-boundary-internal-asr.md) | Data boundary – optional transcription through the internal network | Superseded by 0017 |
| [0011](0011-distribution-signed-dmg.md) | Distribution – signed app outside the App Store | Accepted, amended by 0021, 0031 |
| [0012](0012-menu-bar-ui-and-settings.md) | Control through a menu bar popover and Settings | Accepted, amended by 0014, 0018 |
| [0013](0013-build-structure-xcodegen.md) | Project structure – XcodeGen and the OMSCore package | Accepted, amended by 0024 |
| [0014](0014-sessions-tab-cleanup-editor.md) | Sessions tab, deletion, freeing space and the summary editor | Accepted |
| [0015](0015-system-prompt-in-app.md) | The system prompt is part of the app | Accepted, amended by 0025 |
| [0016](0016-speaker-diarization.md) | Speaker identification in the transcript | Proposed |
| [0017](0017-model-choice-and-claude.md) | Model choice for the summary and optional Claude | Accepted, amended by 0022, 0023 |
| [0018](0018-ui-localization-english-default.md) | UI localization – English as default, Slovak as translation | Accepted |
| [0019](0019-product-name-minutes.md) | Product name Minutes and the app icon | Accepted, amended by 0020, 0021 |
| [0020](0020-app-icon-light-dark.md) | App icon with light and dark appearance | Accepted |
| [0021](0021-first-release-packaging.md) | First release 1.0.0 – file name, version and packaging | Accepted, amended by 0031 |
| [0022](0022-open-source-release.md) | Public open-source repository, any model and Codex | Accepted, amended by 0023 |
| [0023](0023-ai-tool-boundaries-and-job-safety.md) | Narrow AI tool permissions, process groups and one operation for one session | Accepted |
| [0024](0024-apps-folder-per-platform.md) | One folder for each app in `apps/` | Accepted |
| [0025](0025-user-editable-system-prompt.md) | The user edits a copy of the system prompt | Accepted |
| [0026](0026-apache-2-license.md) | Apache License 2.0 | Accepted |
| [0027](0027-model-output-file-name.md) | Model output file name from user instructions | Accepted |
| [0028](0028-site-on-github-pages.md) | User guide on GitHub Pages | Accepted |
| [0029](0029-session-parts-continue-and-merge.md) | Sessions with parts – continue a recording and merge sessions | Proposed |
| [0030](0030-crash-resilient-recording.md) | Recording that survives a crash and recovery of interrupted sessions | Proposed |
| [0031](0031-app-updates-sparkle.md) | App updates with Sparkle and an appcast on GitHub Pages | Accepted |
| [0032](0032-audio-only-recording.md) | Audio-only recording | Proposed |
| [0033](0033-menu-bar-icon-context-menu.md) | Menu of the menu bar icon | Proposed |
| [0034](0034-import-existing-recordings.md) | Import of existing recordings | Proposed |
| [0035](0035-settings-tabs-and-model-data-note.md) | Settings tabs and one data note for all models | Proposed |
| [0036](0036-session-detail-result-first-and-shared-styles.md) | Session detail with the result first, and shared popover styles | Proposed |
