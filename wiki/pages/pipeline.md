# Processing pipeline

Sources: requirements (kept locally), [crash spike](../raw/2026-11-17-crash-recording-spike.md), [import request](../raw/2026-11-18-import-recordings.md) · Updated: 2026-11-18

## Steps after Stop

1. **Save:** `recording.mov` (video + microphone track + system track).
2. **Audio:** ffmpeg creates `audio/mic.wav` and `audio/system.wav` (16 kHz, mono).
   ```
   ffmpeg -i recording.mov -map 0:a:0 -ac 1 -ar 16000 audio/mic.wav
   ffmpeg -i recording.mov -map 0:a:1 -ac 1 -ar 16000 audio/system.wav
   ```
3. **Transcription:** a local engine or a transcription server ([ADR-0010](../../docs/adr/0010-data-boundary-internal-asr.md)) transcribes each track separately. Segments get the speaker `me` or `others`. Older transcripts use `ja` and `ostatní`.
   ```
   whisper-cli -m ggml-large-v3-turbo.bin -l auto --vad -oj -osrt -f audio/system.wav
   ```
4. **Merge:** the app sorts the segments by time into `transcript.json` and `transcript.md`.
5. **Keyframes (optional):** frames at scene changes.
   ```
   ffmpeg -i recording.mov -vf "select='gt(scene,0.3)',showinfo" -vsync vfr frames/scene_%04d.jpg
   ```
6. **Waiting for summary:** the user selects the template, detail level, language and instruction, and clicks **Start summarizing**.
7. **Summary:** `opencode run` with the template and the transcript. For non-sensitive meetings, the user can select Claude (`claude -p`, cloud) – see [ADR-0017](../../docs/adr/0017-model-choice-and-claude.md). The agent can call only `frame-at.sh <hh:mm:ss>` in the session folder; each engine gets the narrowest permissions that it supports ([ADR-0023](../../docs/adr/0023-ai-tool-boundaries-and-job-safety.md)). The agent rules are in the system prompt. The default is `apps/macos/prompts/meeting-summary.md` ([ADR-0015](../../docs/adr/0015-system-prompt-in-app.md)). The summary uses the user's copy in Application Support, which the user can edit ([ADR-0025](../../docs/adr/0025-user-editable-system-prompt.md)).
8. **Output:** `outputs/<date>_meetingsummary_<topic>.md`. A notification with a link.

## Imported files

See [ADR-0034](../../docs/adr/0034-import-existing-recordings.md).

1. **Copy:** the app works in a hidden folder `.<timestamp>.importing` in the sessions folder. The original file does not change.
2. **Audio:** AVFoundation (or ffmpeg for mkv, webm, ogg …) makes `audio/import.m4a` from the first audio track.
   ```
   ffmpeg -i <file> -map 0:a:0 -vn -c:a aac -b:a 128k audio/import.m4a
   ```
3. **Video (optional):** `mov` and `mp4` are copied. ffmpeg copies the video stream of other containers into `recording.mkv` without a new encoding.
   ```
   ffmpeg -i <file> -map 0:V:0 -c copy -an -sn -dn recording.mkv
   ```
4. **Session:** `session.json` with `source: imported`, then a rename to `<timestamp>`. More files in one session are parts without breaks, in the order of their names.
5. **Transcription:** as after Stop. One track, so no speakers.

## Sessions with parts

See [ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md).

1. **Continue or merge:** a session gets a second recording. The app moves the first one to `parts/01/` and adds `parts/02/`, `parts/03/` …
2. **Transcription per part:** each part gets `parts/NN/transcript.json` with times relative to the part. A part that has one already is not transcribed again.
3. **Combine:** the app moves each part by its offset (its start minus the start of part 1) and writes the session transcript. `transcript.md` has a marker line at the start of each part.
4. **Frames:** `parts.tsv` maps a time on the combined timeline to a part video. `frame-at.sh` reads it.
5. **Summary:** the prompt says how many parts the recording has.

## Recording files

Video and audio are written with movie fragments every 10 seconds. After a crash, the files stay readable; at most the last 10 seconds are lost ([ADR-0030](../../docs/adr/0030-crash-resilient-recording.md)). At launch, the app gives an interrupted session its end from the readable media.

## Live transcription (later)

Recording in 30-second blocks and transcription in the background. Then Stop takes only a few seconds. It is not in the MVP scope yet.

## Time estimate (to check)

| Step | 60 min meeting, M-series |
|---|---|
| Audio extraction | < 30 s |
| Transcription with whisper large-v3-turbo | approx. 3–8 min |
| Summary with a model in OpenCode | approx. 1–3 min |
