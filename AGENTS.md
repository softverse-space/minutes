# Rules for agents in this repository

## Language

- Write everything in the repository in English: code, identifiers, commit messages, documentation, ADRs, wiki, prompts and templates.
- Slovak exists only as a translation of the user interface: the String Catalog of the app (`Localizable.xcstrings`, `InfoPlist.xcstrings`) and the `SK` dictionary in `apps/site/index.html`.
- Write new UI texts in English and add the Slovak translation at the same time. On the website, change every text in both languages.
- Write in the spirit of ASD-STE100 Simplified Technical English: short sentences, active voice, simple words, the same word for the same thing.

## Decisions (ADR)

- Record each architectural decision and each change of a decision as an ADR in `docs/adr/`.
- Use the template `docs/adr/0000-template.md`. Number the ADRs in sequence.
- Do not rewrite an accepted ADR. A new decision supersedes it (`Superseded by ADR-XXXX`).
- After each new ADR, update the table in `docs/adr/README.md`.

## LLM wiki

- Read `wiki/index.md` before you start work.
- Maintain the wiki as `wiki/AGENTS.md` describes (ingest, query, lint).
- Record each change of the wiki in `wiki/log.md`.

## Privacy

- Never put recordings, transcripts of real meetings, models, company templates or internal addresses in the repository.
- Keep local-only material in `local/`. Git ignores this folder.
- Do not add API keys. OpenCode, Claude and Codex read keys from the user's own configuration.
