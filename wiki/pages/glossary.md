# Glossary

Updated: 2026-11-18

| Term | Meaning |
|---|---|
| Session | One recording from Start to Stop and all its outputs |
| Transcript | Text of the speech with the start, end, speaker and language of each segment |
| Summary (output) | The result of the model, based on the template |
| Template | Markdown file with the instruction for the model and the structure of the summary (`standard` and custom templates) |
| Detail level | Brief, medium or detailed. It does not depend on the template |
| Custom instruction | Free text that replaces the template |
| Popover | The window that opens when you click the menu bar icon |
| Frame | An image from the video at a given time |
| Keyframe | A frame at a large change of the image (new slide) |
| Engine | Transcription model: local (WhisperKit, whisper.cpp, Parakeet) or a server with an API compatible with OpenAI |
| Track | A separate audio channel: microphone or system |
| Part | One recording from Start (or Continue) to Stop inside a session. See [ADR-0029](../../docs/adr/0029-session-parts-continue-and-merge.md) |
| Continue | Record a new part into an existing session. |
| Merge | Move all parts of a later session into an earlier session. |
| Interrupted session | A session whose last part has no end, because the app or the Mac stopped. See [ADR-0030](../../docs/adr/0030-crash-resilient-recording.md) |
| Import | Make a session from existing audio or video files. The app copies the files. See [ADR-0034](../../docs/adr/0034-import-existing-recordings.md) |
| Imported session | A session with `source: imported` in `session.json`. It cannot get a new recording |
| Combined timeline | The timeline of a session with parts. Time 0 is the start of the first part. |
