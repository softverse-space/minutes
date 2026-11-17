# Open questions and risks

Sources: requirements (kept locally), brief (kept locally), [continue and merge request](../raw/2026-11-17-continue-and-merge-sessions.md) · Updated: 2026-11-17

## Questions

1. Which models in OpenCode can read images? If a model cannot, how do we process frames?
2. Do we have a company Apple Developer Program account and a Developer ID certificate? ([ADR-0011](../../docs/adr/0011-distribution-signed-dmg.md))
3. Do common transcription servers return segments with times (`verbose_json`)?
4. Must the app bundle ffmpeg, or will AVFoundation replace it? (Colleagues possibly do not have Homebrew.)
5. Can colleagues without OpenCode make a summary? Or is OpenCode a required dependency?
6. Default sessions folder: `~/Meetings`?
7. How long do we keep the video? Delete it automatically after N days?
8. Must the MVP already have live transcription? (The brief puts it outside the first version.)
9. Continue and merge sessions: the open questions Q1–Q7 are in the [specification](../../docs/specs/continue-and-merge-sessions.md#16-open-questions).

## Resolved

- Transcription through a server: yes, as an option → [ADR-0010](../../docs/adr/0010-data-boundary-internal-asr.md).
- Distribution: signed .dmg outside the App Store → [ADR-0011](../../docs/adr/0011-distribution-signed-dmg.md).
- Templates: `standard` + custom templates + detail level → [ADR-0007](../../docs/adr/0007-output-templates.md).
- Skill of the current workflow: taken over → [current-manual-workflow](current-manual-workflow.md).

## Risks

- **SK/CS mix:** Whisper detects the language one time and can "translate" Czech into Slovak.
- **Consent to recording:** the participants must know that someone records the meeting.
- **Double audio:** with speakers, the microphone also records the system audio. Recommend headphones.
- **Long meetings:** test a recording of 2+ h (stability, audio drift against the video).
- **macOS permissions:** system updates can reset Screen Recording.
- **Crash during a recording:** the video and audio writers write the file header only at Stop. After a crash, the files are not readable (confirmed by the [spike](../raw/2026-11-17-crash-recording-spike.md)). Movie fragments fix it. See [ADR-0030](../../docs/adr/0030-crash-resilient-recording.md).
- **Stuck transcription state:** after a crash during a transcription, `session.json` keeps `transcription: running`. ADR-0030 proposes a fix at launch.
- **Prompt injection:** a transcript is not trusted input. The engines get narrow tool permissions, but the user's own CLI configuration is outside the app. Not verified yet: a real summary run with each engine after [ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md), and Cancel with the OpenCode 2.x background service. The managed OpenCode agent needs OpenCode 2.x, because the app cannot check the permissions of OpenCode 1.x.
