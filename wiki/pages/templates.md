# Output templates

Sources: AGENTS.md of the original project (kept locally), feedback from Henrich (2026-11-13) · Updated: 2026-11-13

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
