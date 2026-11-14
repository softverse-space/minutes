# ADR-0001: We record decisions as ADRs

- **Status:** Accepted
- **Date:** 2026-11-13
- **Decided by:** Henrich Neuschl

## Context

The project starts as an idea. Many decisions will change. We want to know why we made each decision.

## Decision

- We record each architectural decision as an ADR in `docs/adr/`.
- We do not rewrite an ADR with status `Accepted`. We record a change in a new ADR and mark the old one `Superseded`.
- We can edit an ADR with status `Proposed` until we accept it.

## Consequences

- The decision history is in git and in the text.
- An agent (Claude, OpenCode) must create an ADR when it changes the architecture. The rule is in `AGENTS.md`.
