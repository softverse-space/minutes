# Output templates

Sources: AGENTS.md of the original project (kept locally), feedback from Henrich (2026-11-13) · Updated: 2026-11-15

Decision: [ADR-0007](../../docs/adr/0007-output-templates.md). Files: [`apps/macos/templates/`](../../apps/macos/templates/).

4 choices define the summary: **template**, **detail level**, **language**, **additional instruction**.

| Template | When to use | Default language |
|---|---|---|
| `standard` | Every meeting. Agenda, summary, decisions, tasks, open questions | sk |
| Custom instruction | The user writes what summary they want | sk |

| Detail level | Scope |
|---|---|
| Brief | 1 bullet per topic, half a page |
| Medium | 2–5 bullets per topic, approx. 1 page |
| Detailed | a subsection per topic, arguments, numbers, screen content |

Definitions of the levels: [`_detail-levels.md`](../../apps/macos/templates/_detail-levels.md).

## Custom template

1. Copy `standard.md`.
2. Change `id`, `name` and the instruction body.
3. Save it in the custom templates folder (default `~/Library/Application Support/OfflineMeetingSummary/templates/`).

## Output file name

The Extra or custom instruction can request an output file name. The model returns the name as metadata. The app validates it and saves the summary under that name. If the name exists, the app adds a version suffix. If the name is absent or invalid, the app uses the existing date and topic pattern.

Decision: [ADR-0027](../../docs/adr/0027-model-output-file-name.md).
Source: [Output file name from Extra](../raw/2026-11-15-output-file-name.md).
