# ADR-0005: Transcript processing with OpenCode CLI and an internal model

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

A model that runs internally in the company must prepare the meeting summary (summarization, template). The user already has OpenCode configured for the internal LiteLLM gateway. Sometimes the model must look at a screenshot at a given time.

## Options

1. **`opencode run` as an external process** – uses the existing configuration (provider, model, key). The agent can run a tool that extracts a frame. The app does not manage keys.
2. **Direct call to an OpenAI-compatible API** – fewer dependencies. But the app must manage the key and its own agent loop for frames.

## Decision

We propose option 1. The app calls:

```
opencode run -m <provider/model> --agent meeting-summary -f transcript.md "<instruction from the template>"
```

The model and the agent are in the app Settings. The default is the model from the OpenCode configuration.

## Consequences

- Verified: `opencode run` writes only the model response to stdout. Progress and tools go to stderr.
- The frame tool is in `~/Library/Application Support/OfflineMeetingSummary/bin/frame-at.sh`. The path contains a space, so the instruction puts it in quotes.

- The app never reads the API key.
- We need a custom OpenCode agent `meeting-summary` that has the frame tool (`app/scripts/frame-at.sh`) enabled and no other tools.
- Verify: whether the internal model can read images. If not, frames will go through OCR or a description from a different model.
