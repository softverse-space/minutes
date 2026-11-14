# ADR-0009: LLM wiki as project memory

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The project grows in conversations with agents. Knowledge (model tests, requirements, problems) gets lost between sessions.

## Decision

- We keep an LLM wiki in `wiki/` based on the pattern by Andrej Karpathy.
- `wiki/raw/` = sources that do not change (notes, test results, skill).
- `wiki/pages/` = pages that the agent maintains.
- `wiki/AGENTS.md` = rules for ingest, query and lint.
- ADRs stay in `docs/adr/`. The wiki links to them but does not duplicate them.

## Consequences

- The agent reads `wiki/index.md` at the start of work.
- Each wiki change has an entry in `wiki/log.md`.
