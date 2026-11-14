# ADR-0004: Local transcription engine

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

Meetings are in Slovak, English or a mix of Slovak and Czech. Local transcription runs on the Mac. The output needs timestamps, so that we can find frames from the video.

The current manual procedure (raw (kept locally)):
- Mac: MLX Whisper, model `mlx-community/whisper-large-v3-turbo` (already in the cache), often `language="sk"`.
- Windows: faster-whisper `large-v3-turbo`, CPU int8, `beam_size=5`.

Practical use confirms the quality of `large-v3-turbo` for our meetings.

## Options

1. **WhisperKit (Argmax, CoreML)** – native Swift package, `large-v3-turbo`, Neural Engine, timestamps. No Python and no external process. Model approx. 1.6 GB.
2. **whisper.cpp (`whisper-cli`)** – Metal, `brew install whisper-cpp`, JSON/SRT/VTT, VAD. External process. Used in phase 0.
3. **MLX Whisper** – verified in the current procedure. Needs a Python environment. Not suitable for a signed app for colleagues.
4. **Parakeet TDT 0.6B v3 through CoreML (FluidAudio)** – SK and CS, automatic language detection, very fast. Less verified on our data.

## Decision

Accepted 2026-11-13 – the app uses WhisperKit 1.1.1. The comparison with Parakeet stays open.

- Phase 0 (script): whisper.cpp.
- App: WhisperKit with `large-v3-turbo` as the default. Parakeet v3 as the second local engine after the comparison.
- The app has a `TranscriptionEngine` protocol. The user can change the engine in Settings.
- Transcription through the internal network is a separate option, see [ADR-0010](0010-data-boundary-internal-asr.md).

## Consequences

- The app downloads the model at first start, with the user's consent. The model is not part of the .dmg.
- We must compare accuracy and speed on 3–5 real recordings (SK, EN, SK+CS). We will record the result in the wiki and accept the ADR.
- Whisper detects the language once at the start. With a SK/CS mix, it can "translate" Czech into Slovak. The app will have a language setting (`auto` / `sk` / `cs` / `en`).
