# ADR-0024: One folder for each app in `apps/`

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl
- **Amends:** [ADR-0013](0013-build-structure-xcodegen.md)

## Context

The folder `app/` contained the macOS project in `app/macos/` and, next to it, templates, prompts, scripts, the icon generator and docs. The user guide was in `site/` at the root. A Linux or Windows version had no clear place.

## Options

1. **`apps/<platform>/` for each app, the guide in `apps/site/`** – each app is complete in one folder. A new platform adds a folder. Templates and the prompt are not shared yet.
2. **`apps/<platform>/` and a shared folder for templates and prompts now** – ready for a second app, but the shared folder has only one user today.

## Decision

We select option 1.

| Old path | New path |
|---|---|
| `app/macos/…` | `apps/macos/…` |
| `app/templates/`, `app/prompts/`, `app/scripts/`, `app/design/`, `app/docs/` | `apps/macos/templates/`, `apps/macos/prompts/`, `apps/macos/scripts/`, `apps/macos/design/`, `apps/macos/docs/` |
| `app/README.md`, `app/CHANGELOG.md` | `apps/macos/README.md`, `apps/macos/CHANGELOG.md` |
| `site/` | `apps/site/` |

## Consequences

- Older ADRs and old entries in `wiki/log.md` keep the old paths. Use the table above to find the new path.
- `project.yml` takes templates, prompts and `frame-at.sh` from its own folder. XcodeGen must generate the project again.
- The build folder is now `apps/macos/build/`. A running app from the old path must be closed and built again.
- When a second app needs the templates or the system prompt, we move them to a shared folder with a new ADR.
