# ADR-0030: Recording that survives a crash and recovery of interrupted sessions

- **Status:** Proposed (format decided by the spike, the app tests are open)
- **Date:** 2026-11-17
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0003](0003-screencapturekit-recording.md), [ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)

## Context

[ADR-0029](0029-session-parts-continue-and-merge.md) lets the user continue a session after the app or the Mac stopped. That is useful only when the recorded part is still readable.

### How the recorder writes files today

| File | Writer | When the file becomes readable |
|---|---|---|
| `recording.mov` | `AVAssetWriter`, QuickTime, H.264, no movie fragments | Only after `finishWriting`. The writer writes the movie header (`moov`) at the end |
| `audio/mic.m4a`, `audio/system.m4a` | `AVAudioFile`, AAC in MPEG-4 | Only after `close()`. The header and the packet table come at the end |
| `session.json` | `updateMetadata` | `audioTracks` and `endedAt` come only at Stop |

Without the header, `AVURLAsset`, `AVAudioFile` and `ffprobe` cannot read the file. The audio and video data is on the disk, but no tool knows where the samples are. Tools that repair such files (for example `untrunc`) need a reference file and are not reliable.

Transcription reads the audio with `AVAudioFile(forReading:)` (`AudioConversion.swift`).

The spike of 2026-11-17 confirmed the problem: after `kill -9`, today's `recording.mov` and `.m4a` files are not readable at all (`moov atom not found`). Results: [wiki/raw/2026-11-17-crash-recording-spike.md](../../wiki/raw/2026-11-17-crash-recording-spike.md).

### Events that end a recording without Stop

| # | Event | What the app gets | Data on the disk |
|---|---|---|---|
| E1 | The app crashes, or `kill -9` | Nothing | All bytes that the writer wrote. The kernel keeps them in the file cache and writes them later |
| E2 | Quit in the popover during a recording | `NSApp.terminate` | As E1. The app does not stop the recording before it quits |
| E3 | Restart, shut down or log out from the Apple menu, or an automatic system update | The system asks the app to quit | As E1. The app has no `applicationShouldTerminate` handler |
| E4 | The Mac sleeps (lid closed, low battery) | `NSWorkspace.willSleepNotification` | Not known. ScreenCaptureKit can stop the stream with an error or pause it. To verify |
| E5 | Kernel panic, power loss, a forced restart with the power button | Nothing | Bytes in the file cache that were not written to the disk are lost (typically the last 5–30 seconds) |

Today all five events leave unreadable files. After E1–E5, `session.json` also keeps `transcription: running` when a transcription ran.

## Options

### Part 1: avoid the problem where the app gets a signal (E2, E3, E4)

1. **Stop the recording correctly before the app quits or the Mac sleeps.**
   - E2, E3: `applicationShouldTerminate` returns `.terminateLater`, stops the recording as Stop does, and then calls `reply(toApplicationShouldTerminate: true)`. The system waits for the app.
   - E4: on `willSleepNotification` the app stops the recording. The part ends with the reason `sleep`. After the wake, the app offers to continue ([ADR-0029](0029-session-parts-continue-and-merge.md)).
   - Advantages: no data loss. No change of the file formats.
   - Disadvantages: it does not help in E1 and E5.

There is no alternative to option 1 for these events. We take it in every case.

### Part 2: readable files after E1 and E5

**Video**

1. **Movie fragments.** Set `writer.movieFragmentInterval = 10 s`. The writer writes a short header at the start and then one fragment (`moof` + data) every 10 seconds. A reader reads all complete fragments.
   - Advantages: one property. The file stays `recording.mov`. Loss: at most the last 10 seconds.
   - Disadvantages: to verify that `AVURLAsset` and `ffmpeg` (the frame tool) read the file after a crash, and that `finishWriting` still gives a normal file.

For the video we see no better option.

**Audio**

1. **Fragmented QuickTime audio files.** Write each track with `AVAssetWriter` (audio input, AAC) to `audio/mic.mov` and `audio/system.mov` with `movieFragmentInterval = 10 s`. Keep the silence that fills gaps and the zeros for mute, as today.
   - Advantages: the same technique as the video. Small files (AAC). Loss: at most 10 seconds.
   - Disadvantages: the writer gets `CMSampleBuffer`s instead of `AVAudioPCMBuffer`s. The silence that fills gaps and the zeros for mute must become sample buffers.
   - Spike: the `.m4a` container works the same as `.mov`. `AVAudioFile` reads both, after a crash and after a normal stop. So the file can stay `audio/mic.m4a` and the audio conversion does not change.
2. **AAC in 60-second chunks.** Keep `AVAudioFile`. Close the file every 60 seconds and open the next one (`audio/mic/0001.m4a`, …).
   - Advantages: a closed chunk is always readable with the current reader.
   - Disadvantages: loss: up to 60 seconds. Each AAC file starts with encoder priming (about 2,112 samples, 44 ms). Without a correction, 120 chunks of a 2-hour meeting move the audio by about 5 seconds against the video and the other track. More files and more metadata. Transcription must join the chunks.
3. **PCM WAV at 16 kHz, mono, 16-bit.** Convert each buffer during the recording to the format that transcription uses anyway, and write it to `audio/mic.wav`.
   - Advantages: the simplest format. After a crash, only the header has wrong sizes. The app repairs it from the file size (all data after the header is samples). Transcription needs no conversion. Loss: only the bytes that were not on the disk (E5).
   - Disadvantages: larger files: 1.9 MB per minute per track, about 460 MB for 2 hours and 2 tracks (AAC today: about 2 × 60 MB). 16 kHz is enough for speech recognition, but not for good playback. A server engine (`ServerAsrEngine`) uploads larger files. The free space limits ([ADR-0023](0023-ai-tool-boundaries-and-job-safety.md)) stay valid, because the video is much larger.

### Part 3: less loss after E5 (optional)

- Every 10 seconds (with the `lastAliveAt` heartbeat), call `fsync` on the open media files. Then E5 loses at most about 10 seconds.
- `F_FULLFSYNC` is safer, but slower. The spike measures the cost of both.

## Decision

Decided after the spike of 2026-11-17 ([results](../../wiki/raw/2026-11-17-crash-recording-spike.md)):

1. **Part 1 always:** stop the recording correctly on Quit, on a system restart, shut down or log out, and before sleep.
2. **Video:** movie fragments with an interval of 10 seconds. The file stays `recording.mov`. The spike tested 10 s and 2 s. A crash loses at most one interval.
   - Fragments are parts inside one file, not separate files. A 1-hour recording is still one `recording.mov` with about 360 fragments.
   - The interval does not change the time offset of a recovered track (see Recovery). It changes only how much the last fragment can lose.
   - 10 s is a pragmatic value: a loss of at most 10 s is acceptable for a meeting summary (decided by the user, 2026-11-17). A longer interval (15–30 s) is possible later if the 2-hour test shows a problem with many fragments.
3. **Audio:** audio option 1 with the `.m4a` container. Each track uses `AVAssetWriter`, AAC, `movieFragmentInterval` 10 s (the same as the video). The files stay `audio/mic.m4a` and `audio/system.m4a`. `AudioConversion` and old sessions do not change.
4. **Not selected:**
   - AAC in 60-second chunks (option 2): time drift and up to 60 s loss.
   - PCM WAV (option 3): unreadable after a crash without a header repair, and larger files.
   - AAC in CAF: unreadable after a crash (0 s in the spike).
   - PCM 16 kHz in CAF stays the fallback. It was fully readable after the crash (35 of 35 s), but the files are about 2.7× larger than AAC. Use it only if the fragmented `.m4a` fails with the real ScreenCaptureKit buffers.
5. **`F_FULLFSYNC`** on the open media files every 10 seconds, on a background queue, not on the sample queue. Cost in the spike: about 5 ms. Plain `fsync` on macOS does not empty the disk cache, so it does not protect against a power loss.

**Metadata during the recording**
- The app writes `audioTracks` to `session.json` at the start. It writes the offset when the first sample arrives.
- The app writes `lastAliveAt` to `session.json` every 10 seconds during the recording. It uses the existing 5-second disk check timer.
- A part that ends without Stop gets a reason: `crash` (found at launch), `quit`, `sleep`, `streamError`, `diskFull`.

**Recovery at launch**
- The app finds sessions (and parts) with `endedAt == nil` that do not record now. It marks them as interrupted.
- The app sets `endedAt` from the duration of the readable media, or from `lastAliveAt` when the media is not readable.
- The app checks each media file with `AVURLAsset`. An unreadable file stays on disk and gets the state `unreadable`.
- A recovered AAC track starts about 43 ms late (encoder priming without the edit list, seen in the spike). The offset comes one time, at the start of the file. It does not grow with the number of fragments or with the time (the spike measured 43 ms at 10, 20 and 30 s in a file with 16 fragments). The app does not correct it.
- A transcription with the state `running` from an earlier app process becomes `pending`.
- The app posts a notification with the action **Continue recording** ([ADR-0029](0029-session-parts-continue-and-merge.md), flow F5).

## Spike

Done on 2026-11-17 with synthetic buffers and `SIGKILL` (event E1). Code: [docs/spikes/2026-11-17-crash-recording/](../spikes/2026-11-17-crash-recording/). Results: [wiki/raw/2026-11-17-crash-recording-spike.md](../../wiki/raw/2026-11-17-crash-recording-spike.md).

**Still to verify in the app** (implementation steps 9 and 10, manual tests in the specification):
1. Real ScreenCaptureKit buffers with the fragmented writers, `kill -9` during a recording.
2. E2 Quit, E3 restart from the Apple menu, E4 sleep (what ScreenCaptureKit does), E5 a forced restart (once).
3. A 2-hour recording: open time and seek speed of the fragmented files, the frame tool at the end, drift between the tracks.
4. CPU load of the recording before and after the change.

## Consequences

- E2, E3 and E4 lose no data.
- E1 loses at most 10 seconds. E5 loses at most about 10 seconds (the `F_FULLFSYNC` interval). Not verified for E5.
- `AudioTrackWriter` changes from `AVAudioFile` to `AVAssetWriter`. File names, audio conversion and transcription do not change.
- The stuck transcription state after a crash is fixed for all sessions, also without parts.
- A session that the app cannot recover stays on disk. The app shows a message and does not delete files.
- Sessions recorded before this change keep their files. The app reads both the old and the new audio format.
