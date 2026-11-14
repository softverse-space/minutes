# Overview

The product name is **Minutes** ([ADR-0019](../../docs/adr/0019-product-name-minutes.md)). The original working name was Offline Meeting Summary.

Sources: requirements (kept locally), brief (kept locally) · Updated: 2026-11-13

## Problem

Today I record a meeting in OBS. Then I run ffmpeg, whisper and the agent manually. There are many steps, and I do each step manually.

## Goal

One app in the Mac menu bar. One click starts the recording. After Stop, the app makes a transcript and a summary based on a template.

## Main requirements

- **Privacy:** the video stays on the Mac. Transcription runs locally, optionally through a server. The model that the user sets in OpenCode (local, company or cloud) prepares the summary. For non-sensitive meetings, the user can select Claude or Codex (cloud) for the summary. See [ADR-0022](../../docs/adr/0022-open-source-release.md). See [ADR-0017](../../docs/adr/0017-model-choice-and-claude.md), which replaces ADR-0010.
- **Languages:** SK, EN, SK + CS mix.
- **Source selection:** a screen from the previews in the popover. See [ui](ui.md).
- **Summary:** template (`standard`, custom templates, custom instruction) + detail level (brief, medium, detailed) + language.
- **Image on demand:** the model requests a frame at a given time.
- **Distribution:** signed and notarized .dmg outside the App Store ([ADR-0011](../../docs/adr/0011-distribution-signed-dmg.md)). Guide for colleagues: [site](../../apps/site/index.html).

## Users

- The author (Henrich) – daily meetings, workshops with customers.
- Anyone with a Mac who wants summaries without sending the recording to the cloud.

## Related

[architecture](architecture.md) · [pipeline](pipeline.md) · [roadmap](roadmap.md) · [open-questions](open-questions.md)
