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

## [2026-11-15] decision | User guide on GitHub Pages
- A GitHub Actions workflow publishes `apps/site/` to `https://softverse-space.github.io/minutes/` (ADR-0028).
- The install step links to the latest release. The footer links to the source code (EN and SK).
- ADR: new 0028. Changed: README.md

## [2026-11-17] ingest | Continue and merge sessions
- Source: raw/2026-11-17-continue-and-merge-sessions.md (request from the user).
- Added: docs/specs/continue-and-merge-sessions.md, ADR-0029 and ADR-0030 (both proposed). Not implemented yet.
- Changed: pages/glossary.md, pages/roadmap.md, pages/open-questions.md, docs/adr/README.md.
- Finding: the recorder writes the header of `recording.mov` and of the `.m4a` tracks only at Stop. A crash probably leaves unreadable files. ADR-0030 plans a spike.
- Lint: no new wiki page. The pages ui.md, pipeline.md and architecture.md describe the current state. Update them in step 10 of the implementation plan.

## [2026-11-17] decision | Continue and merge sessions – open questions
- The user accepted the proposals for Q1 (offer to continue: 30 min, 12 h for an interrupted session), Q2 (timeline with real breaks) and Q4 (no Split in the first version).
- Q3, Q5, Q6 and Q7 stay open. Changed: docs/specs/continue-and-merge-sessions.md

## [2026-11-17] decision | Continue and merge sessions – Q3, Q5, Q6, Q7
- Accepted: Q3 (older summaries to `outputs/` of the target), Q5 (merge with the previous session only).
- Q6 changed: the notification action **Continue recording** is in the first version (flow F5).
- Q7: ADR-0030 now has the list of events (crash, Quit, restart, sleep, power loss), the options for video and audio, and the spike matrix. The app stops the recording correctly on Quit, restart and sleep. Audio format: the spike decides between fragmented `.mov` and 16 kHz WAV.
- Changed: docs/specs/continue-and-merge-sessions.md, docs/adr/0030-crash-resilient-recording.md

## [2026-11-17] ingest | Spike: media files after a crash
- Source: raw/2026-11-17-crash-recording-spike.md. Code: docs/spikes/2026-11-17-crash-recording/.
- Confirmed: today's `recording.mov` and `.m4a` are not readable after `kill -9`.
- Movie fragments make video and AAC `.m4a` readable after a crash (loss ≤ fragment interval). `AVAudioFile` reads the fragmented `.m4a`, so the audio conversion stays.
- ADR-0030: decision completed (fragments every 5 s, AAC `.m4a`, `F_FULLFSYNC` every 10 s). App tests E2–E5 are open.
- Changed: docs/adr/0030-crash-resilient-recording.md, docs/specs/continue-and-merge-sessions.md, pages/open-questions.md

## [2026-11-17] decision | Fragment interval 10 s
- The user accepted a loss of up to 10 s after a crash. ADR-0030 and the specification now use a fragment interval of 10 s (was 5 s).
- Clarified: fragments are inside one file, and the AAC start offset (43 ms) is constant. Checked on a file with 16 fragments.
- Changed: docs/adr/0030-crash-resilient-recording.md, docs/specs/continue-and-merge-sessions.md, raw/2026-11-17-crash-recording-spike.md

## [2026-11-17] update | Continue and merge sessions implemented
- OMSCore: session parts, combined transcript, merge with a journal, recovery of interrupted sessions. 111 tests pass.
- App: Continue recording (session detail, list, banner, notification action), Merge with previous session, transcription per part, fragmented video and audio, heartbeat with `F_FULLFSYNC`, correct stop before quit and sleep, recovery at launch, Slovak texts.
- Site: a paragraph about continue and merge (EN and SK).
- Open: the manual tests of the specification (section 14.2) with a real recording.
- Changed: pages/ui.md, pages/pipeline.md, pages/architecture.md, pages/glossary.md, pages/roadmap.md

## [2026-11-17] ingest | App updates
- Source: request from the user (notify about a new version, install it from the app).
- Added: docs/specs/app-updates.md, ADR-0031 (proposed). Not implemented yet.
- Changed: pages/roadmap.md, docs/adr/README.md.

## [2026-11-17] decision | App updates – project links
- The user asked for an open-source section with a link to GitHub in the app.
- Added to docs/specs/app-updates.md: section 7a (About → Open source, problem report, `ProjectLinks`), step 8 of the plan, Q5 (GitHub Issues are off, Discussions are on).
- Changed: docs/adr/0031-app-updates-sparkle.md (proposed).

## [2026-11-17] decision | App updates – implementation
- The user accepted the proposals for Q1–Q5 and asked for the implementation. ADR-0031 is accepted.
- Added: `UpdateController` (Sparkle 2.10.1), `ProjectLinks` in OMSCore with tests, About → Open source, Settings → General → Updates, the popover update row, the blue dot on the menu bar icon, `apps/site/appcast.xml`, `scripts/appcast.sh`, `scripts/appcast_item.py`, the issue template.
- Changed: pages/ui.md, pages/architecture.md, pages/roadmap.md, docs/specs/app-updates.md, docs/adr/README.md, README.md, apps/macos/README.md, CHANGELOG.md, apps/site/index.html (FAQ in EN and SK).
- Open: the EdDSA key pair, GitHub Issues on, the release 1.1.0.

## [2026-11-17] decision | App updates – local releases
- The user decided: releases stay local on the author's Mac. The team has one person.
- GitHub Actions releases are possible later with a new ADR (environment with a reviewer, protected tags, 2FA, pinned actions). Changed: docs/adr/0031-app-updates-sparkle.md.

## [2026-11-17] release | Minutes 1.1.0 and the release skill
- Minutes 1.1.0 (build 2) is on GitHub. The appcast announces it.
- The website and the README showed 1.0.0 after the release. Fixed: they show 1.1.0.
- Added: the project skill `.claude/skills/release/SKILL.md` (complete release procedure), `scripts/set-version.sh`, `scripts/sync-site-version.sh`, `scripts/release_notes.py`.

## [2026-11-17] update | Audio-only recording and the menu of the menu bar icon
- Source: request from the user (record without the screen; quick actions on a right click on the icon).
- App: a Screen switch on the New session tab (audio only, no `recording.mov`); a menu on a right click or a Control-click with Start/Stop recording, Stop transcription, Stop writing minutes, Settings and Quit.
- ADR: new 0032 and 0033 (proposed).
- Site: two points in the recording chapter (EN and SK).
- Open: manual tests with a real recording (audio only, continue, right click).
- Changed: pages/ui.md, pages/architecture.md

## [2026-11-17] release | Minutes 1.2.0
- New: audio-only recording (ADR-0032) and the menu of the menu bar icon (ADR-0033).
- Version 1.2.0, build 3. The first update through Sparkle, from 1.1.0.
- Published: GitHub release v1.2.0, appcast item (EdDSA signature checked), website and README (EN and SK, FAQ about audio only).
- Fixed: `release.sh` wrote the full local path into the `.sha256` file. It now writes only the file name.

## [2026-11-18] update | Import of existing recordings
- Source: [import request](raw/2026-11-18-import-recordings.md).
- App: Import a recording… (New session tab, menu of the menu bar icon) and a drop on the popover. A copy of the file in a hidden staging folder, `audio/import.m4a`, optional video (`recording.mov`, `.mp4` or `.mkv`), transcription at once. More files: one session with parts or separate sessions. ffmpeg for mkv, webm, ogg, opus and other formats.
- ADR: new 0034 (proposed).
- Site and README: a point in the recording chapter and a FAQ item (EN and SK).
- Open: manual tests in the app (drop, file dialog, alert, Cancel, a kill during the import, a 2+ h file).
- Changed: pages/ui.md, pages/pipeline.md, pages/architecture.md, pages/glossary.md, docs/adr/README.md, CHANGELOG.md, README.md, apps/site/index.html.

## [2026-11-18] update | Copy outputs and prompt preview
- Source: discussion with the user. HTML templates and extra context for the model are out of scope: the core is recording, transcript and summary. The user can take the Markdown or the transcript to other tools.
- App: copy button and drag for summaries (Markdown, HTML and RTF on the clipboard), copy button for the transcript, **Show prompt** in the Summary card.
- Site: sum.p3 (EN and SK).
- Changed: pages/ui.md

## [2026-11-19] decision | Settings tabs and one data note for all models
- Source: feedback from the user (the ffmpeg status was in the System prompt section, the OpenCode agent status was not useful, the cloud warning was only for Claude and Codex, the window was small).
- App: a new Models tab, the Summary tab without tools, one data note for all models, window 640 pt wide.
- ADR: new 0035 (proposed), changes the Settings table of 0012.
- Changed: pages/ui.md
- Later the same day: one section layout for all tools (switch, Program, default model, Advanced with an own path), no "(cloud)" label, the Model picker shows only tools that are on, the OpenCode agent name setting is removed. ADR-0015 and ADR-0023 got an "amended by ADR-0035" note.
- Merge with main: main got ADR-0034 (import of recordings), so the Settings decision is now ADR-0035.

## [2026-11-19] release | Minutes 1.3.0
- New: import of existing recordings (ADR-0034), copy and drag of outputs, **Show prompt**, regrouped Settings (ADR-0035).
- Version 1.3.0, build 4. Update through Sparkle from 1.2.0.
- Fixed: a compiler warning (`nonisolated(unsafe)` on a `Sendable` constant in `MarkdownHTML.swift`).

## [2026-11-19] update | User-facing CHANGELOG
- Source: feedback from the user after the 1.3.0 release. The release notes were too long and had links to ADRs.
- Changed: `apps/macos/CHANGELOG.md` (all versions, shorter, no links to ADRs or code), the release notes in `apps/site/appcast.xml` (from the new CHANGELOG; signatures not changed), the release skill (rule for the CHANGELOG), the GitHub release notes of v1.0.0–v1.3.0.
