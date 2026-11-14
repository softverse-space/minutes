# Current manual workflow

Sources: AGENTS.md of the original project (kept locally), brief (kept locally) · Updated: 2026-11-13

The original workflow was a manual project with OBS, ffmpeg, Whisper and an agent that follows `AGENTS.md`. The sources are only local, not in the repository.

## Steps

1. The recording is made outside (OBS). Nobody changes the original.
2. ffmpeg extracts the audio: 16 kHz, mono, 16-bit PCM WAV.
3. A local Whisper `large-v3-turbo` makes the transcript.
   - Mac: MLX Whisper (`mlx-community/whisper-large-v3-turbo`, cache in `~/.cache/huggingface`), often `language="sk"`.
   - Windows: faster-whisper, CPU int8, `beam_size=5`. Package `distribution/offline-transcript-windows/`.
4. Transcript outputs: TXT, SRT, VTT, JSON.
5. The agent checks unclear parts: it transcribes a short section again (`recheck_<from>_<to>`).
6. If the speech depends on the screen, the agent cuts a frame with ffmpeg (e.g. `diagram_4200.png`).
7. The agent asks for the output language and format if the user did not give them.
8. The agent prepares the summary and checks it against the transcript with times.

## Rules that we take over

- Do not invent owners, decisions or deadlines. If they are missing, write `TBA` and the reason.
- Keep decisions apart from proposals and open questions.
- Names from the transcript are uncertain. Check them from the context.
- The summary **never** contains times from the recording.
- Translate headings into the output language. Keep company codes, products and abbreviations.
- Summary name: `<date>_meetingsummary_<topic>.md`. Transcript: `<timestamp>_transcript.*`.
- Use the company summary format only for meetings that require it. It is not the default.

In the app, these rules are in the system prompt [`meeting-summary`](../../apps/macos/prompts/meeting-summary.md). Company templates are in the custom templates folder, not in the repository.

## What we do not take over

- The question about language and format before the summary. In the app, the user selects them in the popover ([ui](ui.md)).
- Integration into the Ready app. The brief proposed it. Now we build a separate app.

## Problems of the current workflow

- Many manual steps and many switches between tools.
- The Windows script takes only the first audio track. It can lose the microphone or the audio of the others.
