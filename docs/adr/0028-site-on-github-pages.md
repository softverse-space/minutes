# ADR-0028: User guide on GitHub Pages

- **Status:** Accepted
- **Date:** 2026-11-15
- **Decided by:** Henrich Neuschl

## Context

The user guide `apps/site/index.html` is one static page with images. The repository is public on GitHub. Colleagues need a link to the guide and to the download.

## Options

1. **Pages from a branch** – no workflow. GitHub serves only the root or `/docs`. The site would have to move.
2. **Pages from a GitHub Actions workflow** – the site stays in `apps/site/` (ADR-0024). A public repository does not pay for the runner minutes.

## Decision

We select option 2.

- `.github/workflows/pages.yml` publishes `apps/site/` when a change in `apps/site/` arrives in `main`. It can also run manually.
- The address is `https://softverse-space.github.io/minutes/`.
- Step 1 of the installation links to the latest GitHub release. The footer links to the source code.

## Consequences

- In Settings → Pages, the source must be "GitHub Actions".
- Each change of the page in `main` publishes it again.
- The page uses no build step. The workflow only uploads the folder.
