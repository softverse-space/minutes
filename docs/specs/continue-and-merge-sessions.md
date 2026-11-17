# Specification: continue and merge sessions

- **Status:** Implemented on 2026-11-17. The manual tests (14.2) are open. See section 17
- **Date:** 2026-11-17
- **Branch:** `feature/continue-and-merge-sessions`
- **Decisions:** [ADR-0029](../adr/0029-session-parts-continue-and-merge.md) (parts, continue, merge), [ADR-0030](../adr/0030-crash-resilient-recording.md) (crash-resilient recording, recovery)
- **Source:** [wiki/raw/2026-11-17-continue-and-merge-sessions.md](../../wiki/raw/2026-11-17-continue-and-merge-sessions.md)

## 1. Problem

One meeting must give one transcript and one summary. Today these events split one meeting into two or more sessions:

| # | Event | What happens today |
|---|---|---|
| S1 | The user clicks **Stop session** by mistake and then **Start session** again | Two sessions, two transcripts, two summaries |
| S2 | The recorder stops because of a stream error or a full disk | The first session is complete. The user starts a second session |
| S3 | The app crashes, or the Mac restarts during the recording | The first session has no `endedAt`, no `audioTracks`, and its media is probably not readable. The user starts a second session after the restart |
| S4 | The meeting has a planned break | Two sessions, or one long recording of the break |

## 2. Goals and non-goals

**Goals**
1. The user continues a stopped or interrupted session. The new recording becomes a part of the same session.
2. The user merges two existing sessions into one session.
3. One combined transcript and one summary for all parts.
4. No new transcription of a part that already has a transcript.
5. A crash or a restart loses at most a few seconds of audio.
6. Sessions with one recording do not change.

**Non-goals (this version)**
- Split a merged session back into separate sessions.
- Cut or edit media.
- Join the media files into one video file.
- Merge more than two sessions in one step. The user repeats the merge.
- Live transcription.

## 3. Terms

Add these terms to the [glossary](../../wiki/pages/glossary.md).

| Term | Meaning |
|---|---|
| Part | One recording from Start (or Continue) to Stop inside a session |
| Continue | Record a new part into an existing session |
| Merge | Move all parts of a later session into an earlier session |
| Interrupted session | A session whose last part has no end, because the app or the Mac stopped |
| Combined timeline | The timeline of a session with parts. Time 0 is the start of the first part |
| Break | The time between the end of one part and the start of the next part |

## 4. User flows

### F1 – Continue a stopped session

1. The user opens a session on the Sessions tab.
2. The session detail shows **Continue recording**. Conditions:
   - No recording runs.
   - The session is idle (no transcription, summary or cleanup).
   - The media of the session was not removed (`mediaRemovedAt == nil`).
3. The user clicks **Continue recording**.
4. The app records a new part with the sources that are selected on the New session tab.
5. The recording view shows the session name and "Part 2". The timer shows the time of the whole session without breaks.
6. After Stop, the app transcribes only the new part and combines the transcript (when automatic transcription is on).

### F2 – Offer to continue on the New session tab

1. The user opens the New session tab.
2. The app shows a banner above **Start session** when one of these conditions is true:
   - The last session stopped less than 30 minutes ago.
   - The last session is interrupted, and it started less than 12 hours ago.
3. The banner text: "Continue the last session? It stopped 4 min ago." or "The last recording was interrupted. Continue it?". Button: **Continue**.
4. **Start session** stays the main button. It starts a new session as today.
5. The user can close the banner. It stays closed for that session.

### F3 – Merge with the previous session

1. The user right-clicks a session on the Sessions tab.
2. The menu has **Merge with previous session…**. The previous session is the next older session in the list.
3. The menu item is disabled when:
   - There is no older session.
   - One of the two sessions is busy or records.
   - The sessions overlap in time.
   - A part has no transcript and no audio.
4. The app shows a confirmation panel in the popover (not an alert, [ADR-0014](../adr/0014-sessions-tab-cleanup-editor.md)):
   - Both sessions with date, time and duration.
   - The break between them.
   - A warning when the break is longer than 60 minutes.
   - The text: "You cannot split the sessions again in the app. Older summaries stay in the session."
5. The user clicks **Merge**.
6. The app merges the sessions and opens the session detail of the result.
7. When all parts have a part transcript, the app combines the transcript at once. Otherwise it transcribes only the missing parts (when automatic transcription is on).

### F4 – Recovery after a crash or restart

1. The app starts.
2. The app finds interrupted sessions and repairs their metadata ([ADR-0030](../adr/0030-crash-resilient-recording.md)).
3. The Sessions tab shows an interrupted session with an orange icon and the help text "The recording was interrupted".
4. The New session tab offers to continue the session (F2).
5. When no media is readable, the session detail says: "The app could not read the recording of this part." The files stay on disk.

### F5 – Continue from a notification

1. A recording ends without Stop. The reasons are a stream error, a full disk, sleep, or a crash or a restart that the app finds at launch.
2. The app posts a notification. Examples:
   - "Recording stopped unexpectedly" (exists today) + the reason.
   - "The last recording was interrupted" (at launch after a crash or a restart).
   - "The recording stopped because the Mac went to sleep" (after the wake).
3. The notification has the action button **Continue recording**.
4. The user clicks **Continue recording**. The app continues the session as in F1. It uses the sources that are selected on the New session tab.
5. When the continue is not possible (no free space, another recording runs, the session is busy), the app opens the popover and shows the reason.
6. A click on the notification itself (not on the action) opens the popover on the session detail.
7. The app does not post this notification after a normal Stop, after Quit and after a system restart from the Apple menu. In these cases the recording ended correctly. The banner on the New session tab (F2) still offers to continue.

## 5. Data model

### 5.1 `session.json`

New fields in `SessionMetadata` (OMSCore, `Session.swift`). All are optional or have a default, so old files decode.

| Field | Type | Meaning |
|---|---|---|
| `parts` | `[SessionPart]`, default `[]` | Empty: one recording in the old layout |
| `lastAliveAt` | `Date?` | Heartbeat during a recording ([ADR-0030](../adr/0030-crash-resilient-recording.md)) |
| `interrupted` | `Bool`, default `false` | The last part ended without Stop |

`SessionPart`:

| Field | Type | Meaning |
|---|---|---|
| `folder` | `String` | `parts/01`, `parts/02`, … (two digits, max. 99 parts) |
| `startedAt` | `Date` | Start of the part |
| `endedAt` | `Date?` | End of the part. `nil` while it records |
| `timeZone` | `String` | Time zone of the part |
| `origin` | `recorded` \| `continued` \| `merged` | How the part came into the session |
| `mergedFrom` | `String?` | Name of the merged session folder |
| `video` | `String?` | File name, relative to the part folder |
| `audioTracks` | `[AudioTrackInfo]` | Paths relative to the part folder |
| `sourceEvents` | `[SourceEvent]` | Times relative to the part start |
| `displayName`, `microphoneName` | `String?` | Sources of the part |
| `transcription` | `StepState` | State of the part transcript |
| `transcriptionEngine` | `String?` | Engine of the part transcript |
| `lastAliveAt` | `Date?` | Heartbeat of the part |
| `interrupted` | `Bool` | The part ended without Stop |
| `endReason` | `stop` \| `crash` \| `quit` \| `sleep` \| `streamError` \| `diskFull`, optional | Why the part ended ([ADR-0030](../adr/0030-crash-resilient-recording.md)) |

Session-level fields with parts:
- `startedAt` = start of part 1. The folder name does not change.
- `endedAt` = end of the last part.
- `duration` = sum of the part durations (without breaks). Add `span` = `endedAt − startedAt` (with breaks).
- `audioTracks`, `video`, `sourceEvents` at session level stay empty.
- `transcription` = `done` only when all parts are `done` and the combined transcript exists.

### 5.2 Folder layout

See [ADR-0029](../adr/0029-session-parts-continue-and-merge.md). Rules:

- `SessionFolder` gets `isMultiPart`, `parts` and `partFolder(_:)` helpers.
- `convertToParts()` moves the files of a session with one recording to `parts/01/`:
  - `recording.mov` → `parts/01/recording.mov`
  - `audio/` → `parts/01/audio/`
  - `<timestamp>_transcript.json` → `parts/01/transcript.json` (the part transcript)
  - The other transcript files (`txt`, `srt`, `vtt`, `md`) stay at the root. The next combine step replaces them.
  - `frames/` stays at the root. Part 1 has offset 0, so the old frames stay correct.
- `convertToParts()` is idempotent. It runs inside `updateMetadata` order: move files first, then save `parts`.

### 5.3 Part map for the frame tool (`parts.tsv`)

The app writes `parts.tsv` at the session root after each change of the parts. One line per part with a video:

```
<offset seconds>\t<duration seconds>\t<part number NN>
0.000\t1834.120\t01
1990.500\t2710.004\t02
```

The model must not change this file. All engines can only read in the session folder or write in `frames/` ([ADR-0023](../adr/0023-ai-tool-boundaries-and-job-safety.md)).

## 6. Combined transcript

### 6.1 Rules

- Part offset = `part.startedAt − parts[0].startedAt`, in seconds.
- Each part transcript has times relative to the part start. The combine step adds the part offset.
- The segments of all parts are sorted by start time (the existing `Transcript.merged`).
- `transcript.md` gets a marker line before the first segment of each part after the first:
  `[00:33:10] --- Part 2. The recording continued after a break of 2 min 36 s. ---`
- `txt`, `srt`, `vtt` and `json` get no marker lines. `json` gets a new optional list `parts` with `start`, `end` and `folder`.

### 6.2 Transcription

`TranscriptionService.transcribe(session)` changes:

1. With no parts: no change.
2. With parts: for each part with `transcription != done` or no `parts/NN/transcript.json`, transcribe the audio tracks of the part and save `parts/NN/transcript.json`. Set the part state.
3. Combine all part transcripts and write the root transcript files.
4. Progress: the done part of all tracks of the parts that need transcription.
5. **Transcribe again** in the session detail transcribes all parts again.
6. A part without audio and without a transcript stops the combine step with the message: "Part 2 has no audio and no transcript."

New OMSCore function: `Transcript.combined(parts: [(offset: Double, transcript: Transcript)]) -> Transcript`. It reuses `merged` and returns the part boundaries.

### 6.3 Summary and prompt

- `meetingDate` and `timeZone` come from part 1.
- `PromptBuilder` adds this text when the session has more than one part:
  "The recording has N parts. The recording stopped between the parts. Lines that start with `---` mark the start of a part. Speech near a break can be cut off. Treat all parts as one meeting."
- The system prompt (`apps/macos/prompts/meeting-summary.md`) does not change. The text goes to the user prompt, so an edited copy of the system prompt ([ADR-0025](../adr/0025-user-editable-system-prompt.md)) still works.
- The session detail shows a hint when a summary is older than the combined transcript: "This summary was made before the sessions were merged."

## 7. Frame tool

`apps/macos/scripts/frame-at.sh` changes:

1. Input stays `<hh:mm:ss>` only.
2. If `parts.tsv` exists in the session folder:
   1. Convert the time to seconds.
   2. Read `parts.tsv` line by line. Check each line with a strict pattern: a number, a number, two digits.
   3. Find the part where `offset ≤ time < offset + duration`.
   4. Local time = time − offset. Video = `parts/<NN>/recording.(mov|mp4|mkv)`.
   5. Check that `parts/<NN>` is a folder and not a link.
   6. No part found: exit 1 with "No recording at this time. The time is in a break between parts."
3. If `parts.tsv` does not exist: no change.
4. The output file stays `frames/at_<hh-mm-ss>.jpg` on the combined timeline.

Tests: extend the frame tool tests in `ProcessRunnerTests.swift` (part 1, part 2, a break, a damaged line, a part number with a path, a link).

## 8. Merge

### 8.1 Preconditions

- Target `A` = the earlier session. Source `B` = the later session.
- `SessionOperations` gets the operation `merge`. `begin(.merge)` must succeed for `A` and for `B`. If it fails for `B`, end it for `A`.
- `B.startedAt ≥ A.endedAt`. An interrupted `A` uses its recovered `endedAt`.
- Each part of `A` and `B` has a part transcript or readable audio.
- `A` and `B` are on the same volume. (They are in the same sessions folder.)
- `A` and `B` together have at most 99 parts.

### 8.2 Steps

1. Write `A/merge-journal.json`: source folder, list of planned moves, state `started`.
2. `A.convertToParts()` when `A` has one recording.
3. If `B` has one recording, plan its files as one part. Otherwise plan each part of `B`.
4. Move each part of `B` to `A/parts/NN/` (next free numbers). Move the part transcript to `A/parts/NN/transcript.json`.
5. Move `B/frames/*` to `A/parts/NN/frames/` (the first part of B).
6. Move `B/outputs/*.md` to `A/outputs/`. On a name conflict, use `SessionNaming` with `_v2`, `_v3`.
7. `A.updateMetadata`: append the parts with `origin = merged` and `mergedFrom = B.name`. Recompute `endedAt`.
8. Write `A/parts.tsv`.
9. Combine the transcript when all parts have a part transcript. Otherwise set `transcription = pending`.
10. Move the folder `B` to the Trash. It contains only `session.json` and empty folders now.
11. Set the journal state `done` and delete the journal.
12. End `merge` for `A` and `B`. Refresh the session list.

### 8.3 Recovery

- At launch, the app looks for `merge-journal.json` in all sessions before any other operation.
- With state `started`, the app does the remaining moves from the journal (each move checks if the source still exists) and continues from step 7.
- When a move is not possible, the app keeps the journal and shows: "A merge did not finish. The files are in <A> and <B>." The app does not delete anything.

## 9. Continue

### 9.1 Steps

1. `AppModel.continueSession(_ session: SessionFolder)`.
2. Preconditions: `phase == .idle`, `operations.begin(.recording, for: session.url)` succeeds, `mediaRemovedAt == nil`, fewer than 99 parts, enough free disk space.
3. `session.convertToParts()` when the session has one recording.
4. Create `parts/NN/` and `parts/NN/audio/`.
5. Append a part with `origin = continued`, `startedAt = now`, `audioTracks` at once ([ADR-0030](../adr/0030-crash-resilient-recording.md)).
6. Start `ScreenRecorder` with `videoURL = parts/NN/recording.mov` and the audio URLs in `parts/NN/audio/`.
7. `activeSession = session`, `activePart = NN`. `recordingStartedAt` = start of the part. The timer shows the previous duration plus the current part.
8. Mute events go to the `sourceEvents` of the part.
9. On Stop: update the part (`endedAt`, `video`, `audioTracks` offsets), `endedAt` of the session, write `parts.tsv`. Then transcribe (automatic transcription) as in F1.

### 9.2 Code changes

- Extract the shared part of `startSession()` and `stopSession()` (`AppModel.swift`) into `startRecording(into:)` and `finishRecording(part:)`. `startSession()` creates the folder and then calls `startRecording`.
- The recording view (`RecordingView.swift`) shows "Part N" when N > 1.

## 10. Crash resilience and recovery

[ADR-0030](../adr/0030-crash-resilient-recording.md) has the analysis, the options and the spike matrix. The work starts with the spike.

### 10.1 Spike (done 2026-11-17)

The spike selected the formats. Results: [wiki/raw/2026-11-17-crash-recording-spike.md](../../wiki/raw/2026-11-17-crash-recording-spike.md). Decision: [ADR-0030](../adr/0030-crash-resilient-recording.md).

### 10.2 Correct stop on Quit, restart and sleep

- Add an `NSApplicationDelegate` (`@NSApplicationDelegateAdaptor` in `OfflineMeetingSummaryApp.swift`).
- `applicationShouldTerminate`: when a recording runs, return `.terminateLater`, run `stopSession()` without automatic transcription, then call `reply(toApplicationShouldTerminate: true)`. Use a limit of 10 seconds.
- `NSWorkspace.willSleepNotification`: stop the recording. The part gets the reason `sleep`.
- `NSWorkspace.didWakeNotification`: post the notification of F5 when the recording stopped because of sleep.
- The **Quit** button in the popover asks for a confirmation during a recording: "A recording runs. Stop it and quit?"

### 10.3 File formats

- `ScreenRecorder.setUpWriter`: set `writer.movieFragmentInterval` to 10 seconds. One file with fragments inside, not more files.
- `AudioTrackWriter`: change from `AVAudioFile` to `AVAssetWriter` with the file type `.m4a`, AAC and `movieFragmentInterval` 10 seconds. Keep the file names `audio/mic.m4a` and `audio/system.m4a`.
  - Append the ScreenCaptureKit sample buffers directly.
  - Keep the silence that fills gaps and the zeros for mute. Build them as PCM buffers and convert them to `CMSampleBuffer` (`CMSampleBufferSetDataBufferFromAudioBufferList`, as in the spike code).
  - Keep the level meter.
- `AudioConversion` does not change. `AVAudioFile` reads the fragmented `.m4a` (spike).
- `F_FULLFSYNC` on the open media files every 10 seconds, on a background queue.
- Fallback when the fragmented `.m4a` fails with real buffers: PCM 16 kHz mono in `.caf` ([ADR-0030](../adr/0030-crash-resilient-recording.md)).

### 10.4 Metadata and recovery

- `AppModel`: write `audioTracks` at the start. Write `lastAliveAt` every 10 seconds (next to `checkDiskSpaceWhileRecording`).
- A part that ends without Stop gets `endReason`: `crash`, `quit`, `sleep`, `streamError`, `diskFull`. Add the field to `SessionPart` and to `SessionMetadata`.
- New `SessionRecovery` (OMSCore, file and metadata logic without AVFoundation) and an app part that checks the media with `AVURLAsset`.
- Recovery at launch in `AppModel.init`, before `refreshSessions()`:
  1. Finish unfinished merges (8.3).
  2. For each session and part with `endedAt == nil`: set `interrupted = true`, `endReason = crash` and `endedAt`.
  3. Set `transcription = pending` where it is `running`.
  4. Post the notification of F5 for the newest interrupted session (only one notification).

### 10.5 Notification action (F5)

- `Notifier.setUp()` registers a category `recording-interrupted` with the action `continue-recording` (title "Continue recording", option `.foreground`).
- `Notifier.post` gets an optional category and the session path in `userInfo`.
- `Notifier` stays without stored state. `setUp` takes a handler `onContinue: @Sendable (URL) -> Void`. `AppModel` passes a handler that calls `continueSession` on the main actor.
- `userNotificationCenter(_:didReceive:)`: for the action `continue-recording`, call the handler. For the default action of this category, open the popover on the session detail. Keep the current behaviour (open the file) for the other notifications.
- The handler checks the session path. It accepts only a folder in the sessions folder that has `session.json`.

## 11. Storage

Change `SessionFolder` in `Session.swift`:

- `sourceMediaURLs`: add `parts/*/recording.*`, `parts/*/audio`, `parts/*/frames`.
- `storageSizes()`: count as media the files in `parts/*/audio/`, `parts/*/frames/` and `parts/*/recording.*`.
- `removeSourceMedia()`: create `parts/*/audio` again, as for the root.
- `SessionLibrary.removeOldVideos`: delete `parts/*/recording.*` too.
- Part transcripts (`parts/*/transcript.json`) are not media. They stay after Free up space.

## 12. UI texts

Write each text in English and add the Slovak translation to `Localizable.xcstrings` at the same time ([ADR-0018](../adr/0018-ui-localization-english-default.md)).

| Key (English) | Slovak |
|---|---|
| Continue recording | Pokračovať v nahrávaní |
| Continue | Pokračovať |
| Continue the last session? It stopped %@ ago. | Pokračovať v poslednej session? Zastavila sa pred %@. |
| The last recording was interrupted. Continue it? | Posledné nahrávanie sa prerušilo. Pokračovať v ňom? |
| Part %lld | Časť %lld |
| Merge with previous session… | Zlúčiť s predchádzajúcou session… |
| Merge | Zlúčiť |
| Break between the sessions: %@ | Prestávka medzi sessions: %@ |
| The break is longer than 60 minutes. Check that it is the same meeting. | Prestávka je dlhšia ako 60 minút. Skontrolujte, či ide o to isté stretnutie. |
| You cannot split the sessions again in the app. Older summaries stay in the session. | Sessions sa v aplikácii nedajú znova rozdeliť. Staršie zápisy v session zostanú. |
| The sessions overlap in time, so you cannot merge them. | Sessions sa časovo prekrývajú, preto sa nedajú zlúčiť. |
| The recording was interrupted | Nahrávanie sa prerušilo |
| The app could not read the recording of this part. | Aplikácia nevie prečítať nahrávku tejto časti. |
| Part %lld has no audio and no transcript. | Časť %lld nemá zvuk ani prepis. |
| This summary was made before the sessions were merged. | Tento zápis vznikol pred zlúčením sessions. |
| A merge did not finish. The files are in %@ and %@. | Zlúčenie sa nedokončilo. Súbory sú v %@ a %@. |
| The last recording was interrupted | Posledné nahrávanie sa prerušilo |
| The recording stopped because the Mac went to sleep | Nahrávanie sa zastavilo, lebo Mac prešiel do režimu spánku |
| A recording runs. Stop it and quit? | Nahrávanie práve beží. Zastaviť ho a ukončiť aplikáciu? |
| Stop and quit | Zastaviť a ukončiť |

The Slovak catalog keeps the word "session" and uses "zápis" for "summary". Check the other words against the catalog before the implementation.

The user guide on the website (`apps/site/index.html`) gets a short section "Continue or merge a session" in English and in the `SK` dictionary ([AGENTS.md](../../AGENTS.md)).

## 13. Implementation plan

Steps 9 and 11 do not depend on the spike. Each step is one commit on `feature/continue-and-merge-sessions`. `swift test` must pass after each step.

| Step | Content | Main files |
|---|---|---|
| 1 | ~~Spike: media after a crash (10.1)~~ Done 2026-11-17 | `docs/spikes/`, `wiki/raw/` |
| 2 | Data model: `SessionPart`, new fields, decoding of old files, `convertToParts()`, `parts.tsv`, overlap check, part offsets | `OMSCore/Session.swift`, tests |
| 3 | Combined transcript and marker lines, prompt text for parts | `OMSCore/Transcript.swift`, `OMSCore/Summary.swift`, tests |
| 4 | Storage with parts (section 11) | `OMSCore/Session.swift`, tests |
| 5 | Frame tool with `parts.tsv` (section 7) | `scripts/frame-at.sh`, `ProcessRunnerTests.swift` |
| 6 | Transcription per part with reuse (6.2) | `TranscriptionService.swift`, `AppModel.swift` |
| 7 | Merge: `SessionOperation.merge`, `SessionMerge` with journal and recovery, UI (F3) | `OMSCore/SessionOperations.swift`, new `OMSCore/SessionMerge.swift`, `SessionsListView.swift` |
| 8 | Continue: refactor of start and stop, `continueSession`, session detail button, recording view (F1) | `AppModel.swift`, `SessionView.swift`, `RecordingView.swift` |
| 9 | Correct stop on Quit, restart and sleep (10.2) | `OfflineMeetingSummaryApp.swift`, `AppModel.swift`, `PopoverView.swift` |
| 10 | File formats, recovery at launch (10.3, 10.4), banner on New session (F2), interrupted icon (F4) | `ScreenRecorder.swift`, `AudioTrackWriter.swift`, `AudioConversion.swift`, new `OMSCore/SessionRecovery.swift`, `IdleView.swift`, `SessionsListView.swift` |
| 11 | Notification action **Continue recording** (F5, 10.5) | `Notifier.swift`, `AppModel.swift` |
| 12 | Localization, website guide, wiki (`ui`, `pipeline`, `architecture`), CHANGELOG, ADR-0029 and ADR-0030 to Accepted | `Localizable.xcstrings`, `apps/site/index.html`, `wiki/`, `apps/macos/CHANGELOG.md` |

## 14. Tests

### 14.1 Unit tests (OMSCore, `swift test`)

- `SessionMetadata` decodes an old `session.json` without `parts`.
- `convertToParts()` moves the files, is idempotent and keeps the frames.
- Part offsets and the combined timeline; the marker lines in `markdown()`.
- Overlap check: overlap, touching parts, break.
- `parts.tsv` content and number format (dot as decimal separator, independent of the locale).
- `SessionOperations`: `merge` holds two sessions; a busy source frees the target.
- `SessionMerge`: one + one part, two + one part, summary name conflict, journal after each step, recovery from each journal state.
- Storage: media size and Free up space with parts; part transcripts stay.
- `SessionRecovery`: `endedAt` from the media duration and from `lastAliveAt`; `running` → `pending`; `endReason = crash`.
- Path check of the notification handler: a folder outside the sessions folder, a folder without `session.json`.
- Frame tool: time in part 1, in part 2, in a break, at the exact part boundary, damaged `parts.tsv`, part number with `../`, link instead of a folder.

### 14.2 Manual tests (app)

1. S1: record 1 min, Stop, click **Continue** in the banner, record 1 min. One session, two parts, one transcript with a marker line, one summary.
2. S2: start a recording, fill the disk below 300 MB. The app stops. Continue after you free space.
3. S3: record 2 min, `kill -9` the app. Start the app. The session is interrupted. The video and both audio tracks are readable and miss at most 10 s. Continue it.
4. S3: force a restart of the Mac during a recording. Same result as test 3.
5. Merge two transcribed sessions. No new transcription. The combined transcript is ready in seconds.
6. Merge a session with removed media and a transcript with a new session. Transcription only of the new part.
7. Summary with frames: the model requests a frame from part 2. The frame shows the correct screen.
8. Free up space and Delete session for a session with parts.
9. Kill the app during a merge (debug delay between the moves). The next launch finishes the merge.
10. Open a session with parts in Minutes 1.0.0. The app does not crash.
11. F5: start a recording, close the lid for 1 min, open it. The notification offers **Continue recording**. A click records part 2.
12. F5: `kill -9` during a recording, start the app. One notification with **Continue recording**. A click records part 2.
13. Quit in the popover during a recording: the confirmation appears; after **Stop and quit** the files are complete.
14. Restart from the Apple menu during a recording: the app stops the recording correctly, no notification after the restart, the banner offers to continue.
15. Record 2 hours. Check the open time of the session, the frame tool at 01:59:00, the drift between the tracks and the CPU load.

## 15. Acceptance criteria

1. After an accidental Stop, the user continues the session with one click and gets one summary.
2. After a crash (E1) at most 10 seconds of the recording is lost. After a power loss (E5) at most about 10 seconds is lost ([ADR-0030](../adr/0030-crash-resilient-recording.md)).
3. The user merges two sessions in the Sessions tab. The result has one combined transcript and one summary.
4. A merge of two transcribed sessions starts no new transcription.
5. The frame tool returns the correct frame for each part.
6. Free up space, Delete session and the automatic video deletion work for sessions with parts.
7. Sessions with one recording behave as before. All existing tests pass.
8. All new UI texts exist in English and in Slovak.
9. After an unexpected stop or a crash, the notification action **Continue recording** starts part 2 of the same session.
10. Quit, a restart from the Apple menu and sleep lose no recorded data.

## 16. Open questions

| # | Question | Proposal or decision |
|---|---|---|
| Q1 | How long after Stop does the New session tab offer to continue? | **Decided (2026-11-17):** 30 minutes; 12 hours for an interrupted session |
| Q2 | Timeline with real breaks or without breaks? | **Decided (2026-11-17):** real breaks (times match the clock, the frame tool stays simple) |
| Q3 | Where do the older summaries of the merged session go? | **Decided (2026-11-17):** `outputs/` of the target with a version suffix |
| Q4 | Must the first version have Split? | **Decided (2026-11-17):** no. The part metadata allows it later |
| Q5 | Merge from a multi-select in the list instead of "with previous session"? | **Decided (2026-11-17):** no. The popover list has no multi-select. Repeat the merge for 3+ sessions |
| Q6 | A notification action **Continue** after an unexpected stop (S2)? | **Decided (2026-11-17):** yes, in the first version. See F5 and 10.5 |
| Q7 | Audio after a crash: fragments or 60-second chunks? | **Decided by the spike (2026-11-17):** video and audio with movie fragments every 10 s (the user accepted a loss of up to 10 s); audio stays AAC `.m4a`. See [ADR-0030](../adr/0030-crash-resilient-recording.md) |

## 17. Implementation notes (2026-11-17)

The implementation follows this specification with these differences:

1. **Commits:** the steps are grouped in three commits: the specification, OMSCore (steps 2–5, 7 and the logic of 10), and the app (steps 6–11).
2. **Quit (10.2):** the **Quit** button in the popover was already disabled during a recording. It stays so. The confirmation "A recording runs. Stop it and quit?" is not necessary. Manual test 13 checks that the button is disabled. `applicationShouldTerminate` covers a restart, a shut down and a log out.
3. **Notification (F5, steps 5 and 6):** an app cannot open its menu bar popover. A failed continue from a notification posts a second notification with the reason. A click on the notification selects the session detail for the next opening of the popover.
4. **Unfinished merge (8.3):** the message is "A merge did not finish. No file was deleted. Check the session <name>." The target session knows its journal, but not the reliable name of the source.
5. **Audio offsets (ADR-0030):** the heartbeat writes the offsets of the audio tracks every 10 seconds, not at the first sample.
6. **Old summaries:** the outputs list marks each summary that is older than the session transcript with a clock. One explanation line is under the list.
7. **Tests:** OMSCore has 111 tests. A separate harness checked the new `AudioTrackWriter` with buffers in the ScreenCaptureKit format: after `SIGKILL` 30 of 35 seconds were readable with `AVAudioFile`; gaps are filled with silence; mute writes silence.

