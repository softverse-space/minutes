# ADR-0027: Model output file name

- **Status:** Accepted
- **Date:** 2026-11-15
- **Decided by:** User

## Context

The Extra instruction can request a file name. The app previously used only the topic and a fixed name pattern.

## Options

1. **Separate name field** – predictable, but duplicates instructions.
2. **Optional model metadata** – supports the existing Extra and custom instructions.

## Decision

Use optional `<!-- filename: name.md -->` metadata after the topic marker. The model follows naming instructions and uses the meeting date in the prompt. The app removes metadata before saving the Markdown.

Accept only a Markdown file name without path separators, colons, control characters or a leading dot. Limit it to 220 UTF-8 bytes to leave room for version suffixes. Invalid or absent names use the existing naming pattern.

This extends the output naming convention in ADR-0006. The app remains responsible for file writes.

## Consequences

Existing model responses still work. Existing names, including case variants, get a version suffix. Writes refuse to overwrite a file created after the name check. Model compliance still depends on the selected model.
