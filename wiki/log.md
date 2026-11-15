# Wiki log

## [2026-11-13] init | Wiki setup
- Created: AGENTS.md, index.md, pages/overview.md, pages/current-manual-workflow.md, pages/architecture.md, pages/pipeline.md, pages/templates.md, pages/roadmap.md, pages/open-questions.md, pages/glossary.md
- Source: requirements from Henrich Neuschl (raw/2026-11-13-zadanie.md)

## [2026-11-13] ingest | Current workflow and brief from the `offline transcript` project
- Sources: raw/2026-11-13-offline-transcript-agents.md, raw/2026-11-13-ready-meeting-capture-brief.md
- Changed: pages/current-manual-workflow.md, pages/templates.md, pages/overview.md, pages/open-questions.md, pages/roadmap.md
- Created: pages/ui.md
- ADR: 0004, 0006, 0007 changed; 0010 replaces 0008; new 0010, 0011, 0012

## [2026-11-13] decision | Feedback from Henrich
- Templates: `standard` and one company template, detail level brief / medium / detailed.
- Transcription can also go through the internal network.
- Distribution: signed app outside the App Store.
- UI: menu bar popover with screen previews, Start session, Start summarizing, Settings.

## [2026-11-13] build | First version of the app
- Created: app/macos (XcodeGen, OMSCore, app). The recording test passed.
- ADR: 0002–0006 accepted; new 0013 (project structure).
- Changed: pages/architecture.md, pages/roadmap.md

## [2026-11-13] decision | Feedback after the first test
- Sessions tab, delete session, free up space, open summaries in VS Code.
- ADR: new 0014, 0012 changed.
- Changed: pages/ui.md, pages/roadmap.md

## [2026-11-13] decision | System prompt in the app
- The summary prompt is in `app/prompts/meeting-summary.md`. It does not depend on the provider. Added rules for transcript errors, names, decisions, dates and Slovak (trigger: a summary from the Qwen model).
- The app creates the OpenCode agent at startup and before each summary.
- ADR: new 0015, 0005 changed.
- Changed: pages/pipeline.md, pages/architecture.md

## [2026-11-13] update | Prompt: English words in Slovak speech
- The prompt has a general method to find the English word behind a garbled word: endings, sounds, spelled-out abbreviations.
- New examples from two more transcripts (GL-ko, MD, views, UI-čko, Git, names of companies and systems).

## [2026-11-13] decision | Speaker identification
- Proposal: local diarization (FluidAudio), names from Teams frames and from context, and confirmation in the app.
- Rejected: voice profiles of colleagues (biometric data, GDPR).
- ADR: new 0016 (Proposed).

## [2026-11-13] decision | Model choice and optional Claude
- The user selects the summary model from the `opencode models` list, separately for each summary.
- Claude Code CLI is an optional cloud engine for non-sensitive meetings. It is off by default.
- ADR: new 0017, replaces 0010 (data boundary).
- Changed: pages/architecture.md, pages/pipeline.md, pages/overview.md (new text replaces the older statement "internal model only")

## [2026-11-13] decision | UI localization, English as default
- UI texts are in English in the code. Slovak is a translation in the String Catalog.
- Settings → General has the option App language. The default is English.
- Templates, the prompt and the default summary language do not change.
- ADR: new 0018, changes 0012.
- Changed: pages/ui.md

## [2026-11-13] update | Menu bar icon
- New icon: a circle with progress (proposal C). The circle is larger than the previous SF Symbol.
- The icon shows 5 states. During transcription it shows the real progress.
- Fixed: the icon disappeared during transcription, because the symbol `waveform.badge.ellipsis` does not exist.
- Changed: pages/ui.md

## [2026-11-13] decision | Name Minutes, app icon, About and guide
- The product name is Minutes. Only the display name changes. The bundle ID, data and Keychain stay the same.
- The new app icon follows the menu bar icon.
- Settings has an About tab.
- site/index.html is a new guide with screenshots (site/images).
- ADR: new 0019.
- Changed: pages/overview.md, pages/ui.md

## [2026-11-13] update | App icon C3e
- The original icon (circle with a wave) was too common. The user selected variant C3e: speech bubbles and a card with a sound wave and tasks.
- Source: app/design/app-icon.svg. ADR-0019 extended (not committed yet).

## [2026-11-14] decision | Icon with light and dark appearance, release 1.0.0
- A new icon replaces C3e: a refined circle with a voice trace, light appearance R2, dark R1 (Icon Composer `.icon`).
- The app file is Minutes.app. The bundle ID does not change. Version 1.0.0.
- Release script app/scripts/release.sh: Developer ID, .dmg, notarization, SHA-256.
- ADR: new 0020 and 0021, 0019 partly replaced.
- Changed: pages/ui.md, pages/roadmap.md

## [2026-11-14] update | New website and README
- site/index.html redesigned: a hero with a dial that fills, and a transcript that changes into a summary. Sections have time labels like transcript lines. Colors follow the icon (paper/ink).
- README.md rewritten for GitHub/GitLab: icon for light and dark mode, screenshots, privacy, installation, build, contributing.

## [2026-11-14] update | README in English, website in two languages
- README.md is in English (entry page on GitHub/GitLab).
- site/index.html: English in the HTML (default), Slovak from the SK dictionary. An EN/SK switch. The page remembers the choice. A Slovak or Czech browser gets Slovak.
- AGENTS.md: added language rules for the README and the website.

## [2026-11-14] update | Screenshots with the menu bar, website changes
- The popover screenshots are new: sample sessions (invented meetings, outside the repository), a clean menu bar with the real Minutes icon, a blurred screen preview.
- Website: the summary card and the notes no longer have a colored side bar.

## [2026-11-14] update | Website: menu bar icon states
- 6 cards replaced the image with the sprite of states. Each card has the icon as SVG in a small menu bar. It takes its color from light or dark mode.
- Transcription fills the circle with a dot, summary and start spin an arc, recording blinks. When motion is reduced, the icons are static.
- New state "Starting or saving". The image site/images/menu-bar-icon-states.png is deleted.

## [2026-11-14] decision | Public repository, any model, Codex, code review
- The repository will be public on GitHub. The company template and internal sources are only in `local/` (git ignores it). The prompt, tests, ADRs and wiki contain no company or client names.
- Summary: OpenCode with any provider (default), Claude and the new Codex as optional cloud engines. Each engine has a `SummaryRunner`. The CLI arguments are in `EngineInvocation` with tests.
- Transcription through a server: any API compatible with OpenAI, with no default address.
- Code review (SwiftUI, Concurrency, architecture, tests): fixed concurrency errors, file reads in the UI, accessibility, plural forms for counts. The project is in Swift 6 mode with strict concurrency and no warnings. 42 tests.
- ADR: new 0022. Changed: pages/overview.md, architecture.md, pipeline.md, roadmap.md, glossary.md, open-questions.md, templates.md, current-manual-workflow.md, raw/README.md, index.md

## [2026-11-14] update | Model choice for each engine
- Each engine has a list of models: OpenCode (`opencode models`), Codex (`codex debug models`, without hidden models), Claude (aliases Sonnet, Opus, Haiku).
- Settings → Summary: a default model for each engine from the list, or "Other model…" with a name that the user types.
- The model choice for a summary shows the models of all enabled engines.

## [2026-11-14] update | Whole repository in English
- Translated all ADRs, the wiki, app docs, the system prompt, the templates, the scripts and the test data to English.
- The prompt keeps Slovak examples of speech-recognition errors on purpose.
- New transcripts label speakers `me` and `others`. Stored values `ja` and `ostatní` stay, so old sessions still load.
- Slovak stays only as a translation of the app UI and the website. AGENTS.md has the new language rules.
- Links to sources that are only local now show plain text.

## [2026-11-14] update | Second code review: tool boundaries and job safety
- Source: code review before the public release (findings P1 and P2).
- OpenCode agent: deny by default, exact frame command, check of the resolved rules. Claude and Codex: narrower read and write access. `frame-at.sh` takes only a time.
- `ProcessRunner` moved to OMSCore: process groups, SIGTERM then SIGKILL, timeout, output limits, `CancellationError`.
- Recorder reports video writer errors and low disk space. Audio tracks stay when the video fails.
- One operation for one session (`SessionOperations`). `updateMetadata` has a lock.
- Server transcription converts and sends one part at a time. A read error no longer looks like the end of the audio.
- 73 tests in OMSCore.
- ADR: new 0023. Changed: pages/architecture.md, pages/pipeline.md, pages/roadmap.md, pages/open-questions.md

## [2026-11-14] update | Follow-up review of ADR-0023
- `OpenCodePolicy` checks the whole rule list against an allowed list. The check fails closed: the managed agent needs OpenCode 2.x.
- `ProcessRunner` decides the output limit after the output is read.
- Cancel of a waiting transcription frees the session at once. A recorder error during the start is not lost.
- 77 tests in OMSCore. ADR-0023 changed before its first commit.

## [2026-11-14] decision | One folder for each app
- `app/` is now `apps/macos/`. All its content (templates, prompts, scripts, design, docs) is in `apps/macos/`. `site/` is now `apps/site/`. A Linux or Windows version gets its own folder in `apps/` (ADR-0024).
- Changed: pages/architecture.md, pages/pipeline.md, pages/templates.md, pages/roadmap.md, pages/overview.md, pages/current-manual-workflow.md (paths only).

## [2026-11-14] decision | The user edits a copy of the system prompt
- The app copies the default system prompt to `~/Library/Application Support/OfflineMeetingSummary/prompts/meeting-summary.md`. All models use the copy (ADR-0025).
- A new default replaces the copy only when the user did not edit it. Settings → Summary has "Edit", "Show in Finder" and "Reset to default…".
- 83 tests in OMSCore.
- ADR: new 0025. Changed: pages/architecture.md, pages/pipeline.md

## [2026-11-14] fix | Cancel of a transcription
- Trigger: Cancel during "Loading model…" took a long time. The button stayed active, and after the stop the session showed only "Not done yet".
- Cancel now stops the wait for the model load at once. The UI shows "Cancelling…" and then "Cancelled" (ADR-0023 extended, not committed yet).

## [2026-11-14] update | Preparation for GitHub
- The default branch is `main`.
- `release.sh` has no hard-coded Apple team ID. It reads `TEAM_ID` or `DEVELOPMENT_TEAM` from `Config/Signing.xcconfig`.
- README: all repository content is in English. The minimum is Xcode 26 (Icon Composer `.icon`).

## [2026-11-14] decision | Apache License 2.0
- The project uses Apache License 2.0. `LICENSE` and `NOTICE` are in the repository root (ADR-0026).
- The names "Minutes" and "Softverse" and the app icon are not licensed.
- ADR: new 0026. Changed: pages/roadmap.md, README.md

## [2026-11-15] ingest | Output file name from Extra
- Changed: pages/templates.md, index.md.
- Added: raw/2026-11-15-output-file-name.md, ADR-0027.
- Lint: the updated page is indexed. ADR-0027 extends the default naming convention.

## [2026-11-15] update | Third-party licenses in the app
- `Resources/Acknowledgements.txt` has the license of Minutes, the MIT license of WhisperKit and its NOTICES (swift-transformers, Apache-2.0).
- Settings → About → Licenses opens the file.
- Changed: pages/roadmap.md
