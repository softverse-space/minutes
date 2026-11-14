# ADR-0016: Speaker identification in the transcript

- **Status:** Proposed
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The transcript identifies only the tracks: "me" (microphone) and "others" (system audio). In a meeting in a room, more people speak into the microphone. When the model writes the summary, it does not know who said what. Thus it assigns tasks and opinions incorrectly.

## Options

1. **Local diarization (FluidAudio, CoreML)** – splits each track by voice into "Person 1, 2, …". Runs on the Mac without a network.
2. **Names from video frames** – when a person speaks, the app captures a frame and reads the names in Teams locally with OCR (Vision).
3. **Names from context** – the model suggests a name from how people address each other in speech and marks it with `(?)`.
4. **Name confirmation in the app** – the user assigns a name to each person in the session detail.
5. **Voice profiles of regular colleagues** – the app would recognize colleagues automatically in later meetings.

## Decision

We propose options 1 to 4.

We reject option 5. A voice profile is biometric data under the GDPR. It would need the consent of each colleague and secure storage. The app does not store voiceprints between meetings.

## Consequences

- Persons are valid only within one session.
- Check the licenses of the FluidAudio models (model cards on Hugging Face) and the diarization quality on a Slovak recording.
- Check if OCR reliably finds the active speaker in Teams.
