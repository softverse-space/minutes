# LLM wiki schema

This wiki is the project memory. The agent writes and maintains it. A person supplies sources and asks questions.

## Layers

1. `raw/` – fixed sources: notes, discussion transcripts, test results, the skill of the current workflow. The agent **never changes** them.
2. `pages/` – wiki pages. The agent creates and updates them.
3. `index.md` – catalog of all pages with a one-sentence description.
4. `log.md` – chronological record of changes (append only).

## Operations

### Ingest (new source)

1. Save the source in `raw/` with the date in the name: `2026-11-13-name.md`.
2. Read the source and find the affected pages in `index.md`.
3. Update the affected pages. Create new pages only for new topics.
4. If the source conflicts with an older statement, do not delete the statement. Mark it and give the new source.
5. If the source changes the architecture, propose an ADR in `docs/adr/`.
6. Update `index.md` and add an entry to `log.md`.

### Query (question)

1. Answer from the wiki pages and give links.
2. If the answer has lasting value, save it as a new page.

### Lint (check)

1. Find pages that `index.md` does not link to.
2. Find conflicts between pages and ADRs.
3. Find outdated statements and open questions that already have an answer.
4. Write the result to `log.md`.

## Conventions

- Language: English.
- Links: relative Markdown links, e.g. `[pipeline](pipeline.md)`.
- At the start of a page: `Sources:` and `Updated:`.
- Do not write decisions in the wiki. Link to the ADR.

## Entry format in log.md

```
## [2026-11-13] ingest | Source title
- Changed: pages/a.md, pages/b.md
```
