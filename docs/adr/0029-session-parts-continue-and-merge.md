# ADR-0029: Sessions with parts – continue a recording and merge sessions

- **Status:** Proposed
- **Date:** 2026-11-17
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0006](0006-session-folder-layout.md), [ADR-0014](0014-sessions-tab-cleanup-editor.md), [ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)

## Context

One meeting can produce more than one session:

- The user clicks **Stop session** by mistake and starts a new session.
- The recording stops because of a stream error or a full disk ([ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)).
- The app stops because of a crash, or the Mac restarts.
- The meeting has a planned break.

Each session then has its own transcript and its own summary. The user wants one transcript and one summary for the whole meeting.

Today one session folder has exactly one recording ([ADR-0006](0006-session-folder-layout.md)). The transcript timeline starts at the start of that recording. The frame tool finds the video only at `recording.mov` in the session folder.

The full specification is in [docs/specs/continue-and-merge-sessions.md](../specs/continue-and-merge-sessions.md).

## Options

1. **Concatenate the media files** (ffmpeg concat) into one `recording.mov` and transcribe again.
   - Advantages: the rest of the pipeline does not change.
   - Disadvantages: slow for long recordings. Needs a full new transcription. Fails when one part is damaged or its media was removed. Loses the original files, or doubles the disk use.
2. **A combined session that only references other session folders.**
   - Advantages: nothing moves.
   - Disadvantages: two places own the same files. Delete, free up space and the operation lock ([ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)) must follow links between folders. The frame tool must read outside its session folder.
3. **One session folder with parts.** Each recording is a part in `parts/NN/`. The app transcribes each part one time and combines the part transcripts into one session transcript.
   - Advantages: one folder owns all files. A part transcript is reused, so a merge of two transcribed sessions needs no new transcription. Works when media was removed. The same model serves "continue" and "merge".
   - Disadvantages: a new folder layout and a metadata change. The frame tool must map a time to a part.

## Decision

We select option 3.

**Folder layout**
- A session with one recording keeps the layout of [ADR-0006](0006-session-folder-layout.md). Nothing changes for it.
- When a session gets a second part, the app converts it to the parts layout. The app moves the recording, the audio and the part transcript of the first recording to `parts/01/`.

```
<sessions folder>/<timestamp>/
  session.json                 # session data and the list of parts
  parts.tsv                    # part map for the frame tool, written by the app
  <timestamp>_transcript.*     # combined transcript of all parts
  frames/                      # frames on the combined timeline
  outputs/                     # summaries
  parts/01/recording.mov
  parts/01/audio/mic.m4a, system.m4a
  parts/01/transcript.json     # part transcript, timeline of the part
  parts/01/frames/             # old frames of a merged session (not used by the model)
  parts/02/…
```

**Metadata**
- `session.json` gets a list `parts`. Each part has its folder, start, end, video, audio tracks, audio source changes, screen, microphone, transcription state and origin (`recorded`, `continued`, `merged`).
- An empty or missing `parts` list means a session with one recording in the old layout. Old sessions load without a migration.
- `startedAt` is the start of the first part. `endedAt` is the end of the last part.

**Combined timeline**
- The offset of a part is its start minus the start of the first part (real time). A break between parts stays visible as a gap in the times.
- Parts must not overlap. The app refuses a merge when the later session started before the earlier session ended.
- `transcript.md` gets a marker line at the start of each part after the first. The prompt tells the model that the meeting has parts and that speech near a break can be cut off.

**Continue**
- The user can continue a stopped session. The app records a new part into the same session folder.
- The New session tab offers to continue the last session when it stopped less than 30 minutes ago or when it was interrupted.

**Merge**
- The user merges a session with the previous session in the Sessions tab. The earlier session is the target.
- The app moves the parts of the later session into the target. It moves the summaries to `outputs/` of the target and resolves name conflicts with `_v2`, `_v3`. It moves the frames to the folder of the part. Then it moves the empty folder of the later session to the Trash.
- The moves are renames on one volume. The app writes a journal before the first move and completes an unfinished merge at the next launch.
- Merge is a new operation in `SessionOperations`. It holds both sessions. Both sessions must be idle.
- Split of a merged session is not in this decision. The part metadata keeps everything that a later split needs.

**Frame tool**
- `frame-at.sh` keeps its input: only a time. In a session with parts, it reads `parts.tsv` in the session folder. Each line has the offset, the duration and the two-digit part number. The script checks each value and builds the path itself.
- A time in a break between parts is an error with a clear message.
- The permissions of OpenCode, Claude and Codex do not change ([ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)).

**Storage**
- Free up space, the automatic video deletion and the size calculation include the files in `parts/`.

## Consequences

- One meeting gives one transcript and one summary, also after a mistake or a crash.
- A merge of two transcribed sessions takes seconds. Only parts without a part transcript need transcription.
- Older summaries of the parts stay in `outputs/`. The user can delete them.
- An older app version can open a session with parts. It shows the combined transcript and can make a summary, but it cannot transcribe the session again and the frame tool finds no video.
- A merge is not reversible in the app in this version. The confirmation must say so.
- Crash recovery needs media files that stay readable after a crash. [ADR-0030](0030-crash-resilient-recording.md) covers that.
- To verify: the frame tool with a time in each part and in a break; free up space and delete for a session with parts; the journal after a kill during a merge.
