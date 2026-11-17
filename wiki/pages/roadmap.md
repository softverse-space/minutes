# Roadmap

Sources: requirements (kept locally), brief (kept locally), [continue and merge request](../raw/2026-11-17-continue-and-merge-sessions.md) · Updated: 2026-11-17

## Phase 0 – script

Automate the current workflow without a new app. Recording stays in OBS.

- [x] Template `standard` and detail levels
- [x] OpenCode agent `meeting-summary` with the rules from the current workflow
- [x] `apps/macos/scripts/process-session.sh` (local transcription and transcription through a server) – written
- [ ] Test the script on 2–3 real recordings
- [ ] Check transcription through a server and image reading by the model

## Phase 1 – MVP app

The acceptance criteria are in the brief (the original brief, kept locally).

- [x] Xcode project `apps/macos/` (XcodeGen), `LSUIElement`, `MenuBarExtra`
- [x] Popover: screen previews, audio sources, Start / Stop session
- [x] Recording: video + microphone + system audio (2 tracks) – checked with a test
- [x] After Stop: transcription (WhisperKit or server)
- [x] Start summarizing: template, detail level, language, instruction → `opencode run`
- [x] Settings (ADR-0012)
- [x] Sessions tab, delete session, free up space, summary editor (ADR-0014)
- [ ] Check on a real long meeting (transcript, summary, frames)
- [x] Developer ID Softverse signature and .dmg – script `apps/macos/scripts/release.sh` (ADR-0021)
- [ ] First notarization of 1.0.0 (needs the profile `minutes-notary`)

## Phase 2 – convenience

- [ ] Postponed steps from the code review: split `AppModel`, Settings and services through protocols, app test target, typed settings keys ([ADR-0022](../../docs/adr/0022-open-source-release.md))
- [x] Second code review: AI tool permissions, process groups, recorder errors, one operation for one session ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md))
- [ ] Before the public release: LICENSE, SECURITY.md, CI (`swift test` and app build), check of the first commit content
- [x] License: Apache License 2.0 (ADR-0026)
- [ ] Publish on GitHub: support link, Releases with a notarized `.dmg`, Homebrew tap

- [ ] Comparison of WhisperKit vs Parakeet v3 vs server (ADR-0004)
- [ ] Process a session again with a different template, session history
- [ ] Check unclear sections with a second transcription
- [ ] Automatic updates (Sparkle)
- [x] Continue a session and merge sessions into one summary – specification [continue-and-merge-sessions](../../docs/specs/continue-and-merge-sessions.md), [ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md) (manual tests open)
- [x] Recording that survives a crash or a restart, recovery of interrupted sessions – [ADR-0030](../../docs/adr/0030-crash-resilient-recording.md) (manual tests open)

## Phase 3 – later

- [ ] Live transcription during the meeting
- [ ] Diarization of more speakers in the system track
- [ ] Fully offline LLM on the Mac
