# ADR-0034: Import of existing recordings

- **Status:** Proposed
- **Date:** 2026-11-18
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0006](0006-session-folder-layout.md), [ADR-0029](0029-session-parts-continue-and-merge.md)

## Context

Until now, the app made a session only from its own recording. Users also have recordings from other tools: a phone dictaphone, a Teams or Zoom export, a camera, an older screen recording. They want the same transcript and the same minutes for these files.

The rest of the pipeline does not need the recorder. Transcription reads the audio files in `audio/`. The summary reads the transcript. The frame tool reads a video with the name `recording.mov`, `recording.mp4` or `recording.mkv`. A session without a video is normal since [ADR-0032](0032-audio-only-recording.md).

The user requirements:

- The original file stays where it is. The app does not change or move it.
- The app processes the file at once.
- The app keeps the video by default, so the minutes can use screen frames.
- When the user imports more files at one time, the app asks: one session or separate sessions.
- The app also reads formats that need ffmpeg (mkv, webm, ogg …).

## Options

1. **Reference the original file** – the session stores the path to the file.
   - Advantages: no copy, no extra disk space.
   - Disadvantages: the session breaks when the user moves or deletes the file. The frame tool would have to read outside the session folder ([ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)). Free up space would delete the user's original.
2. **Copy the file into the session and make an audio track from it** – the session folder owns all its files.
   - Advantages: the session layout stays the same as for a recording. Transcription, merge, free up space and the frame tool do not change. The original file is safe.
   - Disadvantages: a copy of the video needs disk space. On APFS, a copy is a clone and uses no space until a file changes.
3. **Convert the file into a recording of the app** – a new `recording.mov` with two audio tracks.
   - Advantages: no new file names.
   - Disadvantages: a new encoding is slow and loses quality. An imported file has one mixed audio track, so the two tracks would be false.

## Decision

We select option 2.

**Session**
- An imported file becomes a session in the sessions folder. The folder name is the start time (`YYYY-MM-DD_HH-MM-SS`), with `_2`, `_3` when the name exists.
- The start time is the creation date in the media data. Without it, the app uses the creation date of the file, then the time of the import.
- The end is the start plus the duration of the audio.
- `session.json` gets `source: imported` and `importedFileName` (the file name, without its path). A session from an older version has no `source`, which means `recorded`.

**Files**
- The app makes `audio/import.m4a` (AAC) from the first audio track. The session has one audio track, so the transcript has no speakers (`me`, `others`).
- With the setting **Keep the video of imported files** (default on), the app keeps the video:
  - `mov` → `recording.mov`, `mp4` and `m4v` → `recording.mp4`: a copy of the file.
  - Other containers: ffmpeg copies the first video stream, without a new encoding, into `recording.mkv`. A cover picture of an audio file is not a video.
- AVFoundation reads m4a, mp3, wav, aiff, caf, flac, aac, mp4, mov and m4v. ffmpeg reads mkv, mka, webm, ogg, oga, opus, avi, wma, wmv, flv, 3gp, mpg, mpeg, ts and mts, and the files that AVFoundation cannot open. Without ffmpeg, the app tells the user to install it.

**More files**
- The app asks: **One session** or **Separate sessions**. A drop on the popover shows the question in the popover. The file dialog and the menu of the menu bar icon show an alert, because the popover is closed.
- One session: each file is a part (`parts/01`, `parts/02` …, [ADR-0029](0029-session-parts-continue-and-merge.md)), in the order of the file names as Finder sorts them. The parts follow one another without breaks. Part 1 starts at the start time of the first file.

**Safety**
- The app copies and converts into a hidden folder `.<name>.importing` in the sessions folder. When all files are ready, it writes `session.json` and renames the folder. The session list does not show hidden folders.
- Cancel and an error remove the hidden folder. At launch, the app removes hidden folders of imports that a crash or a quit stopped. They hold only copies.
- Before the import, the app checks that the disk has 2 GB plus the size of the files free.
- An import is an operation in `SessionOperations` (`importing`). The app does not install an update during an import ([ADR-0031](0031-app-updates-sparkle.md)).
- One import runs at a time. A recording can run at the same time.

**After the import**
- When **Transcribe automatically** is on (default), the transcription starts at once.
- An imported session cannot get a new recording (Continue). Its time after the end is not real time. Merge with another session works by the rules of [ADR-0029](0029-session-parts-continue-and-merge.md).

**Entry points**
- The button **Import a recording…** on the New session tab.
- A drop of files on the popover.
- **Import a recording…** in the menu of the menu bar icon ([ADR-0033](0033-menu-bar-icon-context-menu.md)).

## Consequences

- The user gets a transcript and minutes for any recording, also without the Screen Recording permission.
- A video import needs disk space for the copy, except on APFS.
- The model sees no speakers in a transcript of an imported file. Speaker diarization ([ADR-0016](0016-speaker-diarization.md)) can add them later.
- The order of the parts follows the file names, not the dates in the files. A real break between the files is not visible.
- An older app version ignores `source` and `importedFileName`. When it saves the session, these fields are lost, and the session counts as recorded.
- Free up space and the automatic video deletion include `recording.mp4` and `recording.mkv`.
- To verify: an import of a file longer than 2 hours; Cancel during the conversion; a kill during the import; a full disk; a frame from an imported mp4 and mkv; free up space of an imported session; a merge of an imported session with a recorded one.
