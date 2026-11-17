# Spike: media files after a crash

Date: 2026-11-17. Mac: Apple M1 Pro, macOS 27.3, Swift 6.4.2, ffmpeg from Homebrew.

Code: [docs/spikes/2026-11-17-crash-recording/](../../docs/spikes/2026-11-17-crash-recording/) (`writer.swift`, `check.swift`).

## Method

- `writer` writes synthetic media in real time with the same APIs and settings as the app (`AVAssetWriter` H.264 QuickTime for video; `AVAudioFile` AAC for audio as in `AudioTrackWriter`).
- Video: 1280×720, 10 fps, the brightness shows the second. Audio: 48 kHz stereo float, 440 Hz tone with a 1 kHz beep at 0, 10, 20, 30 s.
- Crash: after 35 s the process sends `SIGKILL` to itself (the same as `kill -9`, event E1 of ADR-0030). It writes during the kill.
- Normal stop: 20 s, then `finishWriting` or `close`.
- `check` reports: `AVURLAsset` duration, the decoded end of the last sample with `AVAssetReader`, and `AVAudioFile` length. `ffprobe` and the frame tool command (`ffmpeg -ss`) were also run.

## Results after SIGKILL at 35 s

| Variant | AVURLAsset / AVAssetReader | AVAudioFile | ffprobe | Readable |
|---|---|---|---|---|
| Video, today (no fragments) | error -11829 | – | moov atom not found | 0 s |
| Video, fragments 10 s | 30.1 s | – | 30.0 s | 30 of 35 s |
| Video, fragments 2 s | 34.1 s | – | 34.0 s | 34 of 35 s |
| Audio, today (`AVAudioFile` AAC `.m4a`) | error -11829 | error | moov atom not found | 0 s |
| Audio, AAC in `.caf` (`AVAudioFile`) | 0.0 s | 0.0 s | – | 0 s |
| Audio, `AVAssetWriter` AAC `.mov`, no fragments | error | error | – | 0 s |
| Audio, `AVAssetWriter` AAC `.mov`, fragments 10 s | 30.0 s | 30.0 s | – | 30 of 35 s |
| Audio, `AVAssetWriter` AAC `.m4a`, fragments 10 s | 30.0 s | 30.0 s | 30.04 s | 30 of 35 s |
| Audio, `AVAssetWriter` AAC `.m4a`, fragments 2 s | 34.0 s | 34.0 s | 34.05 s | 34 of 35 s |
| Audio, PCM 16 kHz `.wav` (`AVAudioFile`) | 0.0 s | 0.0 s | – | 0 s; 35 s after a header repair |
| Audio, PCM 16 kHz `.caf` (`AVAudioFile`) | 35.0 s | 35.0 s | 35.0 s | 35 of 35 s |

## Results after a normal stop (20 s)

| Variant | AVURLAsset | AVAudioFile | Note |
|---|---|---|---|
| Video, fragments 10 s | 20.0 s | – | Has `moov` + `mvex` + `moof` |
| Audio, `AVAssetWriter` AAC `.m4a`, fragments 10 s | 20.0 s | 20.0 s | 235 KB (today's writer: 285 KB) |
| Audio, `AVAssetWriter` AAC `.mov`, fragments 10 s | 20.0 s | 20.0 s | |
| Audio, PCM 16 kHz `.caf` | 20.0 s | 20.0 s | 629 KB (about 2.7× AAC) |

## Other checks

- **Frame tool:** `ffmpeg -ss 00:00:25` on the crashed fragmented video gives a frame. Its brightness (luma 168) matches second 25 (expected ≈ 166–175).
- **Timeline:** the decoded beeps of the crashed fragmented `.m4a` are at 0.05, 10.05 and 20.05 s. After a normal stop they are at 0.0, 10.0 s. The crashed file has a constant offset of about 44–50 ms (AAC encoder priming without the edit list). The offset does not grow with the time.
- **Offset with many fragments:** the crashed `.m4a` with 2 s fragments is one file with 16 fragments inside. The beeps at 10, 20 and 30 s are all 43 ms late. The offset does not grow with the fragments.
- **Loss:** with fragments the loss is at most one fragment interval (10 s → 5 s lost in this run, 2 s → 1 s lost).
- **fsync cost** (2 MB written between calls, 10 rounds): `fsync` median 0.4 ms; `F_FULLFSYNC` median 5.0 ms, max 8.5 ms.

## Not tested in this spike

- Real ScreenCaptureKit buffers in the app (the spike uses synthetic buffers).
- E2–E5 of ADR-0030: Quit, restart from the Apple menu, sleep, power loss.
- Open time and seek speed of a 2-hour file with many fragments.
- Drift between the tracks in a 2-hour recording.
