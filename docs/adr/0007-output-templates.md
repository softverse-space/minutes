# ADR-0007: Templates, detail level and custom instruction

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

During processing, the user wants to select a template, a detail level (brief, medium, detailed) and a language. The user also wants to write a custom instruction for the summary. Usually a standard meeting summary is sufficient. Some company meetings have a verified format.

## Decision

4 independent choices set the output:

| Choice | Values | Default |
|---|---|---|
| Template | `standard`, custom templates, "Custom instruction" | `standard` |
| Detail level | `strucna`, `stredna`, `detailna` | from the template, else `stredna` |
| Output language | `sk`, `en`, `cs`, … | from the template, else `sk` |
| Additional instruction | free text | empty |

- A template is a Markdown file with YAML front matter: `id`, `name`, `description`, `frames` (`never` | `auto` | `always`), `detail`, `language`.
- `app/templates/_detail-levels.md` defines the detail levels once.
- "Custom instruction" = no template. The user's text sets the full structure of the summary.
- Custom templates are in the folder that the user sets in the app (default `~/Library/Application Support/OfflineMeetingSummary/templates/`).
- The summary never contains times from the recording.

## Consequences

- The app includes the `standard` template. The company template from the current procedure is only local, in the custom templates folder ([ADR-0022](0022-open-source-release.md)).
- We will add more templates only when we need them.
